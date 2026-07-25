# frozen_string_literal: true

module Kit::Remember
  class Planner
    NOTE_BY_BUCKET = {
      "commitments_i_made" => ["Commitments", "Commitments.md"],
      "commitments_others_made" => ["Commitments", "Commitments.md"],
      "commitments_unknown" => ["Commitments", "Commitments.md"],
      "decisions" => ["Decisions", "Decisions.md"],
      "open_loops" => ["Open Loops", "Open Loops.md"]
    }.freeze

    attr_reader :extract, :extract_path, :vault_dir

    def initialize(extract:, extract_path:, vault_dir:)
      @extract = extract
      @extract_path = File.expand_path(extract_path)
      @vault_dir = File.expand_path(vault_dir)
    end

    def plan
      operations = item_operations
      operations << inbox_operation(operations)

      {
        "slug" => extract.fetch("slug"),
        "title" => extract.fetch("title", "Untitled Extract"),
        "input" => {
          "extract_json" => extract_path,
          "transcript_json" => extract.dig("input", "transcript_json"),
          "source_file" => extract.dig("input", "source_file")
        },
        "vault" => vault_dir,
        "review_required" => extract.fetch("review_required", true),
        "warnings" => Array(extract["warnings"]),
        "counts" => counts_by_bucket,
        "operations" => operations
      }
    end

    private

    def item_operations
      Array(extract["items"]).filter_map do |item|
        relative_path = NOTE_BY_BUCKET[item["bucket"]]
        next unless relative_path

        {
          "kind" => "item",
          "item_id" => item.fetch("id"),
          "path" => File.join(vault_dir, *relative_path),
          "section" => "From #{extract.fetch('title', 'Untitled Extract')}",
          "content" => render_item(item)
        }
      end
    end

    def inbox_operation(operations)
      {
        "kind" => "extract_summary",
        "extract_id" => extract.fetch("slug"),
        "path" => File.join(vault_dir, "Inbox", "Kit Inbox.md"),
        "content" => render_inbox_summary(operations)
      }
    end

    def render_item(item)
      citation = item.fetch("citation", {})
      owner = item["owner"].to_s.empty? ? "unknown" : item["owner"]
      source = "#{extract.fetch('title', 'Untitled Extract')} @ #{citation['timestamp'] || 'unknown'}"
      transcript = citation["transcript_path"] || extract.dig("input", "transcript_json")
      quote = citation["quote"].to_s
      speaker = [citation["speaker"], citation["raw_speaker"]].compact.join(" / ")

      lines = []
      lines << "<!-- kit:item #{item.fetch('id')} -->"
      lines << "- [ ] #{item['text']} _(#{item['status'] || 'possible'}, owner: #{owner}, source: #{source})_"
      lines << "  - Type: #{item['type']}"
      lines << "  - Bucket: #{item['bucket']}"
      lines << "  - Notice: #{extract_path}"
      lines << "  - Transcript: #{transcript}" if transcript
      lines << "  - Speaker: #{speaker}" unless speaker.empty?
      lines << "  - Quote: #{quote.inspect}" unless quote.empty?
      lines << "<!-- /kit:item #{item.fetch('id')} -->"
      lines.join("\n")
    end

    def render_inbox_summary(operations)
      lines = []
      lines << "<!-- kit:extract #{extract.fetch('slug')} -->"
      lines << "## #{extract.fetch('title', 'Untitled Extract')}"
      lines << ""
      lines << "- Review required: #{extract.fetch('review_required', true) ? 'yes' : 'no'}"
      lines << "- Notice: #{extract_path}"
      transcript = extract.dig("input", "transcript_json")
      lines << "- Transcript: #{transcript}" if transcript
      lines << "- Items remembered: #{operations.length}"
      counts_by_bucket.each { |bucket, count| lines << "- #{bucket}: #{count}" }
      Array(extract["warnings"]).each { |warning| lines << "- Warning: #{warning}" }
      lines << "<!-- /kit:extract #{extract.fetch('slug')} -->"
      lines.join("\n")
    end

    def counts_by_bucket
      counts = Hash.new(0)
      Array(extract["items"]).each do |item|
        counts[item["bucket"]] += 1
      end
      counts.sort.to_h
    end
  end
end
