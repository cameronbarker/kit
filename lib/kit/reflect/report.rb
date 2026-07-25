# frozen_string_literal: true

require "fileutils"
require "time"

module Kit::Reflect
  class Report
    attr_reader :vault_dir, :me, :now

    def initialize(vault_dir:, items:, warnings:, me: nil, now: Time.now)
      @vault_dir = File.expand_path(vault_dir)
      @items = items
      @warnings = warnings
      @me = clean(me)
      @now = now
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
      history = brief_history

      {
        "schema_version" => 1,
        "kind" => "kit_reflect",
        "generated_at" => now.utc.iso8601,
        "vault" => vault_dir,
        "artifact_path" => artifact_path,
        "filters" => {
          "me" => me,
          "period" => "weekly"
        },
        "counts" => counts(sections),
        "sections" => sections,
        "items" => normalized,
        "brief_history" => history,
        "warnings" => warnings
      }
    end

    private

    def normalized_items
      @items.map { |item| Kit::Surface::Trust.normalize_item(item) }
            .reject { |item| item["rejected"] }
    end

    def build_sections(items)
      trusted = items.reject { |item| item["needs_review"] }
      trusted_open = trusted.select { |item| open?(item) }
      trusted_completed = trusted.select { |item| completed?(item) }
      trusted_open_commitments = trusted_open.select { |item| commitment?(item) }
      trusted_completed_commitments = trusted_completed.select { |item| commitment?(item) }
      no_due_date = trusted_open_commitments.select { |item| no_due_date?(item) }

      {
        "follow_through_snapshot" => follow_through_snapshot(trusted_open_commitments, trusted_completed_commitments),
        "what_keeps_slipping" => no_due_date,
        "commitment_load" => {
          "waiting_on_me" => trusted_open_commitments.select { |item| waiting_on_me?(item) },
          "waiting_on_others" => trusted_open_commitments.select { |item| waiting_on_others?(item) },
          "unclassified" => trusted_open_commitments.reject { |item| waiting_on_me?(item) || waiting_on_others?(item) }
        },
        "decision_bottlenecks" => trusted_open.select { |item| decision?(item) },
        "open_loop_pressure" => trusted_open.select { |item| open_loop?(item) },
        "needs_review_backlog" => items.select { |item| open?(item) && item["needs_review"] },
        "insufficient_signal" => insufficient_signal
      }
    end

    def follow_through_snapshot(open_commitments, completed_commitments)
      total = open_commitments.length + completed_commitments.length
      ratio = completion_ratio(completed_commitments.length, total)

      [
        "Current checkbox snapshot: #{completed_commitments.length} trusted accepted commitment#{plural(completed_commitments.length)} completed, #{open_commitments.length} still open.",
        "Trusted completion ratio: #{ratio.nil? ? 'n/a' : ratio}."
      ]
    end

    def counts(sections)
      load = sections.fetch("commitment_load")
      open_commitments = load.values.flatten.uniq { |item| item["id"] }
      completed_commitments = @items.map { |item| Kit::Surface::Trust.normalize_item(item) }
                                    .reject { |item| item["rejected"] || item["needs_review"] }
                                    .select { |item| completed?(item) && commitment?(item) }
      total = open_commitments.length + completed_commitments.length

      {
        "trusted_open_commitments" => open_commitments.length,
        "trusted_completed_commitments" => completed_commitments.length,
        "trusted_completion_ratio" => completion_ratio(completed_commitments.length, total),
        "waiting_on_me" => load.fetch("waiting_on_me").length,
        "waiting_on_others" => load.fetch("waiting_on_others").length,
        "open_decisions" => sections.fetch("decision_bottlenecks").length,
        "open_loops" => sections.fetch("open_loop_pressure").length,
        "needs_review" => sections.fetch("needs_review_backlog").length,
        "no_due_date_commitments" => sections.fetch("what_keeps_slipping").length
      }
    end

    def completion_ratio(completed, total)
      return nil if total.zero?

      (completed.to_f / total).round(2)
    end

    def brief_history
      dir = File.join(vault_dir, "Weekly Briefs")
      files = Dir.glob(File.join(dir, "Brief - *.md"))
      dates = files.map do |path|
        match = File.basename(path).match(/\ABrief - (\d{4}-\d{2}-\d{2})\.md\z/)
        match && match[1]
      end.compact.sort

      {
        "count" => dates.length,
        "first_date" => dates.first,
        "latest_date" => dates.last
      }
    end

    def insufficient_signal
      [
        "Recurring failure patterns: insufficient repeated structured evidence in v1.",
        "Meeting closure quality: insufficient signal without calendar or meeting analytics.",
        "Project ownership clarity: insufficient signal without structured project ownership data.",
        "People/team operating observations: intentionally not inferred in v1.",
        "Monthly trends: not implemented in v1."
      ]
    end

    def render_markdown(payload)
      lines = []
      lines << "# Weekly Reflection: #{reflection_date}"
      lines << ""
      lines << "- Generated: #{payload['generated_at']}"
      lines << "- Vault: #{payload['vault']}"
      lines << "- Period: weekly"
      lines << "- Trusted open commitments: #{payload.dig('counts', 'trusted_open_commitments')}"
      lines << "- Trusted completed commitments: #{payload.dig('counts', 'trusted_completed_commitments')}"
      lines << "- Needs review: #{payload.dig('counts', 'needs_review')}"
      lines << ""
      render_text_section(lines, "Follow-through snapshot", payload.dig("sections", "follow_through_snapshot"))
      render_item_section(lines, "What keeps slipping", payload.dig("sections", "what_keeps_slipping"))
      render_load_section(lines, payload.dig("sections", "commitment_load"))
      render_item_section(lines, "Decision bottlenecks", payload.dig("sections", "decision_bottlenecks"))
      render_item_section(lines, "Open-loop pressure", payload.dig("sections", "open_loop_pressure"))
      render_item_section(lines, "Needs review backlog", payload.dig("sections", "needs_review_backlog"), review: true)
      render_brief_history(lines, payload["brief_history"])
      render_text_section(lines, "Insufficient signal", payload.dig("sections", "insufficient_signal"))
      render_warnings(lines, payload["warnings"])
      lines.join("\n") + "\n"
    end

    def render_load_section(lines, load)
      lines << "## Commitment load"
      lines << ""
      load = load || {}
      render_inline_item_group(lines, "Waiting on me", load["waiting_on_me"])
      render_inline_item_group(lines, "Waiting on others", load["waiting_on_others"])
      render_inline_item_group(lines, "Unclassified", load["unclassified"])
      lines << ""
    end

    def render_inline_item_group(lines, title, items)
      items = Array(items)
      lines << "### #{title}"
      if items.empty?
        lines << "- None found."
        return
      end

      items.each { |item| lines << "- #{item['text']} (`#{item['id']}`)" }
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
      values = Array(values)
      values.each { |value| lines << "- #{value}" }
      lines << "- None found." if values.empty?
      lines << ""
    end

    def render_brief_history(lines, history)
      history ||= {}
      lines << "## Brief history"
      lines << ""
      lines << "- Weekly briefs found: #{history['count'].to_i}"
      if history["first_date"] && history["latest_date"]
        lines << "- Date range: #{history['first_date']} to #{history['latest_date']}"
      else
        lines << "- Date range: none found"
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
      File.join(vault_dir, "Reflections", "Reflection - #{reflection_date}.md")
    end

    def reflection_date
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

    def no_due_date?(item)
      item["due_date"].to_s.strip.empty?
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
