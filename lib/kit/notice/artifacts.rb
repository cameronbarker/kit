# frozen_string_literal: true

require "fileutils"
require "json"

module Kit::Notice
  class Artifacts
    attr_reader :payload, :extracts_dir, :out_path

    def initialize(payload:, extracts_dir: DEFAULT_EXTRACTS_DIR, out_path: nil)
      @payload = payload
      @extracts_dir = File.expand_path(extracts_dir)
      @out_path = out_path && File.expand_path(out_path)
    end

    def write!
      FileUtils.mkdir_p(File.dirname(json_path))
      FileUtils.mkdir_p(File.dirname(markdown_path))

      result = payload.merge(
        "outputs" => {
          "json" => json_path,
          "md" => markdown_path
        }
      )

      File.write(json_path, JSON.pretty_generate(result) + "\n")
      File.write(markdown_path, render_markdown(result))
      result
    end

    def json_path
      @json_path ||= if out_path&.end_with?(".json")
                       out_path
                     elsif out_path
                       "#{out_path}.json"
                     else
                       File.join(extracts_dir, "json", "#{payload.fetch('slug')}.notice.json")
                     end
    end

    def markdown_path
      @markdown_path ||= if out_path&.end_with?(".md")
                           out_path
                         elsif out_path&.end_with?(".json")
                           out_path.sub(/\.json\z/, ".md")
                         elsif out_path
                           "#{out_path}.md"
                         else
                           File.join(extracts_dir, "md", "#{payload.fetch('slug')}.notice.md")
                         end
    end

    private

    def render_markdown(result)
      lines = []
      lines << "# Notice: #{result['title']}"
      lines << ""
      lines << "Source: #{result.dig('input', 'transcript_json')}"
      lines << "Generated: #{result['generated_at']}"
      lines << "Review required: yes"
      result.fetch("warnings", []).each { |warning| lines << "Warning: #{warning}" }
      lines << ""

      section(lines, "Commitments I Made", result, "commitments_i_made", checkbox: true)
      section(lines, "Commitments Others Made", result, "commitments_others_made", checkbox: true)
      section(lines, "Commitments Needing Review", result, "commitments_unknown", checkbox: true)
      section(lines, "Decisions", result, "decisions")
      section(lines, "Open Loops", result, "open_loops")

      lines.join("\n") + "\n"
    end

    def section(lines, title, result, bucket, checkbox: false)
      items = result.fetch("items", []).select { |item| item["bucket"] == bucket }
      lines << "## #{title}"
      lines << ""
      if items.empty?
        lines << "_None found._"
      else
        items.each do |item|
          marker = checkbox ? "- [ ]" : "-"
          lines << "#{marker} #{item['text']} #{metadata(item)}"
        end
      end
      lines << ""
    end

    def metadata(item)
      citation = item.fetch("citation", {})
      parts = [item["status"], item["owner"], citation["timestamp"]].compact
      "_(#{parts.join(', ')})_"
    end
  end
end
