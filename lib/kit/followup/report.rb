# frozen_string_literal: true

require "time"

module Kit::Followup
  class Report
    attr_reader :vault_dir, :me, :overdue, :waiting_on_me_only, :waiting_on_others_only, :now

    def initialize(vault_dir:, items:, warnings:, me: nil, overdue: false, waiting_on_me_only: false, waiting_on_others_only: false, now: Time.now)
      @vault_dir = File.expand_path(vault_dir)
      @items = items
      @warnings = warnings
      @me = clean(me)
      @overdue = overdue
      @waiting_on_me_only = waiting_on_me_only
      @waiting_on_others_only = waiting_on_others_only
      @now = now
    end

    def to_h
      normalized = filtered_items
      sections = build_sections(normalized)

      {
        "schema_version" => 1,
        "kind" => "kit_followup",
        "generated_at" => now.utc.iso8601,
        "vault" => vault_dir,
        "filters" => {
          "me" => me,
          "overdue" => overdue,
          "waiting_on_me" => waiting_on_me_only,
          "waiting_on_others" => waiting_on_others_only
        },
        "counts" => counts(sections),
        "sections" => sections,
        "items" => normalized,
        "warnings" => warnings
      }
    end

    private

    def filtered_items
      items = @items.map { |item| normalize_item(item) }
                    .select { |item| commitment?(item) }
                    .reject { |item| item["completion"] == "completed" || item["rejected"] }

      items = items.select { |item| !item["needs_review"] && no_due_date?(item) } if overdue
      items = items.select { |item| waiting_on_me_candidate?(item) } if waiting_on_me_only
      items = items.select { |item| waiting_on_others_candidate?(item) } if waiting_on_others_only
      items
    end

    def normalize_item(item)
      normalized = Kit::Surface::Trust.normalize_item(item)
      due_date = due_date(normalized)
      normalized.merge(
        "due_date" => due_date,
        "followup_reason" => followup_reason(normalized, due_date),
        "nudge" => nudge(normalized)
      )
    end

    def build_sections(items)
      trusted = items.reject { |item| item["needs_review"] }

      {
        "waiting_on_me" => trusted.select { |item| waiting_on_me?(item) },
        "waiting_on_others" => trusted.select { |item| waiting_on_others?(item) },
        "needs_renegotiation" => trusted.select { |item| no_due_date?(item) },
        "needs_review" => items.select { |item| item["needs_review"] }
      }
    end

    def counts(sections)
      {
        "waiting_on_me" => sections.fetch("waiting_on_me").length,
        "waiting_on_others" => sections.fetch("waiting_on_others").length,
        "needs_renegotiation" => sections.fetch("needs_renegotiation").length,
        "needs_review" => sections.fetch("needs_review").length,
        "total" => sections.values.flatten.uniq { |item| item["id"] }.length
      }
    end

    def followup_reason(item, due_date)
      return "needs_review" if item["needs_review"]
      return "no_due_date" if due_date.nil?

      "open_trusted"
    end

    def nudge(item)
      if waiting_on_me?(item)
        "Quick update on: #{item['text']}"
      else
        "Checking in on: #{item['text']}"
      end
    end

    def no_due_date?(item)
      item["due_date"].nil?
    end

    def due_date(item)
      value = item["due_date"] || item["due"] || item["Due"] || item["Due Date"] || item["Due date"]
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def waiting_on_me?(item)
      return false if me.nil?

      item["bucket"] == "commitments_i_made" && item["owner"].to_s.strip.casecmp?(me)
    end

    def waiting_on_me_candidate?(item)
      waiting_on_me?(item)
    end

    def waiting_on_others?(item)
      item["bucket"] == "commitments_others_made"
    end

    def waiting_on_others_candidate?(item)
      waiting_on_others?(item)
    end

    def commitment?(item)
      item["bucket"].to_s.start_with?("commitments_")
    end

    def warnings
      values = Array(@warnings)
      return values unless me.nil?

      values + ["Missing --me or KIT_ME; waiting-on-me classification is disabled."]
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
