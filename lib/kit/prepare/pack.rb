# frozen_string_literal: true

require "fileutils"
require "time"

module Kit::Prepare
  class Pack
    attr_reader :vault_dir, :person, :me, :now

    def initialize(vault_dir:, person:, me: nil, now: Time.now)
      @vault_dir = File.expand_path(vault_dir)
      @person = clean(person)
      @me = clean(me)
      @now = now
      raise Error, "missing person" if @person.nil?
    end

    def write
      payload = to_h
      FileUtils.mkdir_p(File.dirname(payload.fetch("artifact_path")))
      File.write(payload.fetch("artifact_path"), render_markdown(payload))
      payload
    end

    def to_h
      parsed = Kit::Surface::Parser.new(vault_dir: vault_dir).parse
      items = matched_items(parsed.fetch("items"))
      sections = build_sections(items)

      {
        "schema_version" => 1,
        "kind" => "kit_prepare",
        "generated_at" => now.utc.iso8601,
        "vault" => vault_dir,
        "artifact_path" => artifact_path,
        "filters" => {
          "person" => person,
          "me" => me
        },
        "counts" => counts(sections),
        "sections" => sections,
        "items" => items,
        "warnings" => parsed.fetch("warnings")
      }
    end

    private

    def matched_items(items)
      items.map { |item| normalize_item(item) }
           .reject { |item| item["completion"] == "completed" || item["rejected"] }
           .select { |item| person_match?(item) }
    end

    def normalize_item(item)
      Kit::Surface::Trust.normalize_item(item)
    end

    def person_match?(item)
      needle = person.downcase
      match_fields(item).any? { |value| value.downcase.include?(needle) }
    end

    def match_fields(item)
      %w[owner speaker text quote source].map do |key|
        value = item[key].to_s.strip
        value.empty? ? nil : value
      end.compact
    end

    def build_sections(items)
      trusted = items.reject { |item| item["needs_review"] }

      {
        "commitments" => trusted.select { |item| commitment?(item) },
        "open_loops" => trusted.select { |item| item["bucket"] == "open_loops" },
        "recent_decisions" => trusted.select { |item| item["bucket"] == "decisions" }.last(5),
        "needs_review" => items.select { |item| item["needs_review"] }
      }
    end

    def commitment?(item)
      item["bucket"].to_s.start_with?("commitments_")
    end

    def counts(sections)
      {
        "commitments" => sections.fetch("commitments").length,
        "open_loops" => sections.fetch("open_loops").length,
        "decisions" => sections.fetch("recent_decisions").length,
        "needs_review" => sections.fetch("needs_review").length,
        "total" => sections.values.sum(&:length)
      }
    end

    def artifact_path
      File.join(vault_dir, "1-1s", "#{safe_person_filename} Prep.md")
    end

    def safe_person_filename
      person.gsub(/[\/\\:]/, "-").gsub(/\s+/, " ").strip
    end

    def render_markdown(payload)
      lines = []
      lines << "# Prep: #{payload.dig('filters', 'person')}"
      lines << ""
      lines << "- Generated: #{payload['generated_at']}"
      lines << "- Person: #{payload.dig('filters', 'person')}"
      lines << "- Vault: #{payload['vault']}"
      lines << "- Matched items: #{payload.dig('counts', 'total')}"
      lines << ""
      render_markdown_section(lines, "Open Commitments", payload.dig("sections", "commitments"))
      render_markdown_section(lines, "Open Loops", payload.dig("sections", "open_loops"))
      render_markdown_section(lines, "Recent Related Decisions", payload.dig("sections", "recent_decisions"))
      render_markdown_section(lines, "Needs Review", payload.dig("sections", "needs_review"), review: true)
      render_warnings(lines, payload["warnings"])
      lines.join("\n") + "\n"
    end

    def render_markdown_section(lines, title, items, review: false)
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
        lines << "- [ ] #{prefix}#{item['text']} (`#{item['id']}`)"
        lines << "  - Status: #{item['status'].to_s.empty? ? 'unknown' : item['status']}"
        lines << "  - Owner: #{item['owner'].to_s.empty? ? 'unknown' : item['owner']}"
        lines << "  - Source: #{item['source']}" unless item["source"].to_s.empty?
        lines << "  - Notice: #{item['notice']}" unless item["notice"].to_s.empty?
        lines << "  - Transcript: #{item['transcript']}" unless item["transcript"].to_s.empty?
        lines << "  - Speaker: #{item['speaker']}" unless item["speaker"].to_s.empty?
        lines << "  - Quote: #{item['quote']}" unless item["quote"].to_s.empty?
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

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
