# frozen_string_literal: true

require "time"

module Kit::Surface
  class Report
    SECTION_KEYS = %w[
      needs_review
      i_made
      waiting_on_others
      open_loops
      recent_decisions
    ].freeze

    attr_reader :vault_dir, :me, :needs_review_only, :now

    def initialize(vault_dir:, items:, warnings:, me: nil, needs_review_only: false, now: Time.now)
      @vault_dir = File.expand_path(vault_dir)
      @items = items
      @warnings = warnings
      @me = clean(me)
      @needs_review_only = needs_review_only
      @now = now
    end

    def to_h
      normalized = filtered_items
      attention = attention_items(normalized)
      sections = build_sections(attention)

      {
        "schema_version" => 1,
        "kind" => "kit_surface",
        "generated_at" => now.utc.iso8601,
        "vault" => vault_dir,
        "filters" => {
          "me" => me,
          "needs_review_only" => needs_review_only
        },
        "counts" => counts(attention),
        "sections" => sections,
        "items" => normalized,
        "warnings" => @warnings
      }
    end

    private

    def filtered_items
      items = @items.map { |item| normalize_item(item) }
      return items unless needs_review_only

      items.select { |item| item["needs_review"] }
    end

    def normalize_item(item)
      Trust.normalize_item(item)
    end

    def attention_items(items)
      items.reject { |item| item["rejected"] }
    end

    def build_sections(items)
      open = items.select { |item| item["completion"] == "open" }
      actionable = open.reject { |item| item["needs_review"] }

      {
        "needs_review" => open.select { |item| item["needs_review"] },
        "i_made" => actionable.select { |item| item["bucket"] == "commitments_i_made" && mine?(item) },
        "waiting_on_others" => actionable.select { |item| item["bucket"] == "commitments_others_made" },
        "open_loops" => actionable.select { |item| item["bucket"] == "open_loops" },
        "recent_decisions" => actionable.select { |item| item["bucket"] == "decisions" }.last(5)
      }
    end

    def counts(items)
      open = items.count { |item| item["completion"] == "open" }
      completed = items.count { |item| item["completion"] == "completed" }
      needs_review = items.count { |item| item["completion"] == "open" && item["needs_review"] }

      {
        "open" => open,
        "completed" => completed,
        "needs_review" => needs_review,
        "i_made" => items.count { |item| item["completion"] == "open" && item["bucket"] == "commitments_i_made" },
        "waiting_on_others" => items.count { |item| item["completion"] == "open" && item["bucket"] == "commitments_others_made" },
        "open_loops" => items.count { |item| item["completion"] == "open" && item["bucket"] == "open_loops" },
        "decisions" => items.count { |item| item["completion"] == "open" && item["bucket"] == "decisions" }
      }
    end

    def mine?(item)
      return true if me.nil?

      item["owner"].to_s.strip.casecmp?(me)
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
