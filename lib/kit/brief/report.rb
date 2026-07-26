# frozen_string_literal: true

require "fileutils"
require "time"

module Kit::Brief
  class Report
    attr_reader :vault_dir, :me, :now, :ai

    def initialize(vault_dir:, items:, warnings:, me: nil, now: Time.now, ai: false)
      @vault_dir = File.expand_path(vault_dir)
      @items = items
      @warnings = warnings
      @me = clean(me)
      @now = now
      @ai = ai
    end

    def write
      payload = to_h
      FileUtils.mkdir_p(File.dirname(payload.fetch("artifact_path")))
      File.write(payload.fetch("artifact_path"), render_markdown(payload))
      payload
    end

    def to_h
      normalized = normalized_items
      sections = build_sections(normalized)

      payload = {
        "schema_version" => 1,
        "kind" => "kit_brief",
        "generated_at" => now.utc.iso8601,
        "vault" => vault_dir,
        "artifact_path" => artifact_path,
        "filters" => {
          "me" => me
        },
        "counts" => counts(sections),
        "sections" => sections,
        "items" => normalized,
        "warnings" => warnings
      }
      ai ? payload.merge("ai_draft" => ai_draft(normalized)) : payload
    end

    private

    def normalized_items
      @items.map { |item| normalize_item(item) }
            .reject { |item| item["rejected"] }
    end

    def normalize_item(item)
      Kit::Surface::Trust.normalize_item(item)
    end

    def build_sections(items)
      trusted = items.reject { |item| item["needs_review"] }
      trusted_open = trusted.select { |item| open?(item) }
      trusted_completed = trusted.select { |item| completed?(item) }
      commitments = trusted_open.select { |item| commitment?(item) }

      {
        "what_moved" => trusted_completed.select { |item| commitment?(item) },
        "waiting_on_me" => commitments.select { |item| waiting_on_me?(item) },
        "waiting_on_others" => commitments.select { |item| waiting_on_others?(item) },
        "open_commitments_unclassified" => commitments.reject { |item| waiting_on_me?(item) || waiting_on_others?(item) },
        "decisions_needed" => trusted_open.select { |item| decision?(item) },
        "open_loops" => trusted_open.select { |item| open_loop?(item) },
        "needs_review" => items.select { |item| open?(item) && item["needs_review"] },
        "recommended_next_actions" => recommended_next_actions(commitments),
        "stakeholder_update_draft" => stakeholder_update_draft(trusted_completed, trusted_open),
        "insufficient_history" => [
          "Insufficient history in v1."
        ],
        "insufficient_signal" => [
          "Risks to watch: Insufficient signal in v1.",
          "People support signals: Insufficient signal in v1."
        ]
      }
    end

    def counts(sections)
      {
        "what_moved" => sections.fetch("what_moved").length,
        "waiting_on_me" => sections.fetch("waiting_on_me").length,
        "waiting_on_others" => sections.fetch("waiting_on_others").length,
        "open_commitments_unclassified" => sections.fetch("open_commitments_unclassified").length,
        "decisions_needed" => sections.fetch("decisions_needed").length,
        "open_loops" => sections.fetch("open_loops").length,
        "needs_review" => sections.fetch("needs_review").length,
        "recommended_next_actions" => sections.fetch("recommended_next_actions").length,
        "total" => factual_item_count(sections)
      }
    end

    def factual_item_count(sections)
      %w[
        what_moved
        waiting_on_me
        waiting_on_others
        open_commitments_unclassified
        decisions_needed
        open_loops
      ].flat_map { |key| sections.fetch(key) }.uniq { |item| item["id"] }.length
    end

    def recommended_next_actions(commitments)
      commitments.first(5).map do |item|
        {
          "item_id" => item["id"],
          "text" => nudge(item)
        }
      end
    end

    def stakeholder_update_draft(completed, open)
      bullets = []
      moved = completed.select { |item| commitment?(item) }
      waiting = open.select { |item| commitment?(item) }
      decisions = open.select { |item| decision?(item) }
      loops = open.select { |item| open_loop?(item) }

      bullets << "Draft: moved #{moved.length} trusted commitment#{plural(moved.length)}." unless moved.empty?
      bullets << "Draft: tracking #{waiting.length} open trusted commitment#{plural(waiting.length)}." unless waiting.empty?
      bullets << "Draft: #{decisions.length} decision#{plural(decisions.length)} need attention." unless decisions.empty?
      bullets << "Draft: #{loops.length} open loop#{plural(loops.length)} remain visible." unless loops.empty?
      bullets << "Draft: no trusted movement or open items found." if bullets.empty?
      bullets
    end

    def nudge(item)
      case item["bucket"]
      when "commitments_i_made"
        "Send a quick update on: #{item['text']}"
      when "commitments_others_made"
        "Check in on: #{item['text']}"
      else
        "Clarify next owner/date for: #{item['text']}"
      end
    end

    def render_markdown(payload)
      lines = []
      lines << "# Weekly Brief: #{brief_date}"
      lines << ""
      lines << "- Generated: #{payload['generated_at']}"
      lines << "- Vault: #{payload['vault']}"
      lines << "- Trusted facts: #{payload.dig('counts', 'total')}"
      lines << "- Needs review: #{payload.dig('counts', 'needs_review')}"
      lines << ""
      render_item_section(lines, "What moved", payload.dig("sections", "what_moved"))
      render_item_section(lines, "What stalled / open - waiting on me", payload.dig("sections", "waiting_on_me"))
      render_item_section(lines, "What stalled / open - waiting on others", payload.dig("sections", "waiting_on_others"))
      render_item_section(lines, "What stalled / open - unclassified", payload.dig("sections", "open_commitments_unclassified"))
      render_text_section(lines, "What changed since last week", payload.dig("sections", "insufficient_history"))
      render_item_section(lines, "Decisions needed", payload.dig("sections", "decisions_needed"))
      render_text_section(lines, "Risks to watch", ["Insufficient signal in v1."])
      render_item_section(lines, "Open loops", payload.dig("sections", "open_loops"))
      render_text_section(lines, "People support signals", ["Insufficient signal in v1."])
      render_item_section(lines, "Needs review", payload.dig("sections", "needs_review"), review: true)
      render_text_section(lines, "Stakeholder update draft", payload.dig("sections", "stakeholder_update_draft"))
      render_ai_draft(lines, payload["ai_draft"])
      render_actions(lines, payload.dig("sections", "recommended_next_actions"))
      render_warnings(lines, payload["warnings"])
      lines.join("\n") + "\n"
    end

    def ai_draft(items)
      query = ["weekly brief", me].compact.join(" ")
      retrieval = Kit::Retrieval.new(limit: 5).retrieve(query)
      provider = Kit::AI.provider(ENV.fetch("KIT_AI_PROVIDER", "mock"))
      draft = provider.brief_draft_bullets(items: items, retrieval_hits: retrieval.fetch("hits", []))
      {
        "provider" => provider.name,
        "status" => "draft",
        "retrieval" => retrieval,
        "bullets" => Array(draft["bullets"]),
        "warnings" => Array(draft["warnings"]) + Array(retrieval["warnings"])
      }
    end

    def render_ai_draft(lines, draft)
      return unless draft

      lines << "## AI Draft Brief Bullets"
      lines << ""
      Array(draft["bullets"]).each do |bullet|
        lines << "- [draft] #{bullet['text']}"
      end
      lines << "- None found." if Array(draft["bullets"]).empty?
      lines << ""
    end

    def render_item_section(lines, title, items, review: false)
      lines << "## #{title}"
      items = Array(items)
      if items.empty?
        lines << ""
        lines << "- None found."
        lines << ""
        return
      end

      items.each do |item|
        prefix = review ? "[needs review] " : ""
        lines << ""
        lines << "- #{prefix}#{item['text']} (`#{item['id']}`)"
        lines << "  - Status: #{item['status'].to_s.empty? ? 'unknown' : item['status']}"
        lines << "  - Owner: #{item['owner'].to_s.empty? ? 'unknown' : item['owner']}"
        lines << "  - Source: #{item['source']}" unless item["source"].to_s.empty?
        lines << "  - Due: #{item['due_date']}" unless item["due_date"].to_s.empty?
      end
      lines << ""
    end

    def render_text_section(lines, title, values)
      lines << "## #{title}"
      lines << ""
      Array(values).each { |value| lines << "- #{value}" }
      lines << "- None found." if Array(values).empty?
      lines << ""
    end

    def render_actions(lines, actions)
      lines << "## Recommended next actions"
      actions = Array(actions)
      if actions.empty?
        lines << ""
        lines << "- None found."
        lines << ""
        return
      end

      actions.each do |action|
        lines << ""
        lines << "- #{action['text']} (`#{action['item_id']}`)"
      end
      lines << ""
    end

    def render_warnings(lines, warnings)
      warnings = Array(warnings)
      return if warnings.empty?

      lines << "## Warnings"
      warnings.each { |warning| lines << "- #{warning}" }
      lines << ""
    end

    def artifact_path
      File.join(vault_dir, "Weekly Briefs", "Brief - #{brief_date}.md")
    end

    def brief_date
      now.strftime("%Y-%m-%d")
    end

    def open?(item)
      item["completion"] == "open"
    end

    def completed?(item)
      item["completion"] == "completed"
    end

    def commitment?(item)
      item["bucket"].to_s.start_with?("commitments_")
    end

    def decision?(item)
      item["bucket"] == "decisions"
    end

    def open_loop?(item)
      item["bucket"] == "open_loops"
    end

    def waiting_on_me?(item)
      return false if me.nil?

      item["bucket"] == "commitments_i_made" && item["owner"].to_s.strip.casecmp?(me)
    end

    def waiting_on_others?(item)
      item["bucket"] == "commitments_others_made"
    end

    def warnings
      values = Array(@warnings)
      return values unless me.nil?

      values + ["Missing --me or KIT_ME; waiting-on-me classification is disabled."]
    end

    def plural(count)
      count == 1 ? "" : "s"
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
