# frozen_string_literal: true

require "fileutils"

module Kit::Remember
  class Notebook
    attr_reader :plan, :dry_run

    def initialize(plan:, dry_run: false)
      @plan = plan
      @dry_run = dry_run
    end

    def apply
      files = {}
      plan.fetch("operations").each do |operation|
        path = operation.fetch("path")
        files[path] ||= read_note(path)
        files[path] = apply_operation(files[path], operation)
      end

      files.each do |path, content|
        next if dry_run

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      plan.merge(
        "dry_run" => dry_run,
        "files" => files.keys.sort,
        "item_count" => plan.fetch("operations").count { |operation| operation["kind"] == "item" }
      )
    end

    private

    def read_note(path)
      return File.read(path) if File.file?(path)

      "# #{File.basename(path, '.md')}\n"
    end

    def apply_operation(content, operation)
      case operation.fetch("kind")
      when "item"
        upsert_item(content, operation)
      when "extract_summary"
        upsert_extract_summary(content, operation)
      else
        content
      end
    end

    def upsert_item(content, operation)
      id = operation.fetch("item_id")
      block = operation.fetch("content")
      pattern = managed_block_pattern("kit:item", id)
      return content.sub(pattern, block) if content.match?(pattern)

      append_to_section(content, operation.fetch("section"), block)
    end

    def upsert_extract_summary(content, operation)
      id = operation.fetch("extract_id")
      block = operation.fetch("content")
      pattern = managed_block_pattern("kit:extract", id)
      return content.sub(pattern, block) if content.match?(pattern)

      append_block(content, block)
    end

    def append_to_section(content, section, block)
      heading = "## #{section}"
      text = ensure_trailing_newline(content)
      unless text.include?("#{heading}\n")
        return append_block(text, "#{heading}\n\n#{block}")
      end

      lines = text.lines
      heading_index = lines.index { |line| line.chomp == heading }
      insert_at = lines.length
      ((heading_index + 1)...lines.length).each do |index|
        if lines[index].start_with?("## ")
          insert_at = index
          break
        end
      end

      lines.insert(insert_at, "\n#{block}\n")
      lines.join
    end

    def append_block(content, block)
      "#{ensure_trailing_newline(content)}\n#{block}\n"
    end

    def ensure_trailing_newline(content)
      content.end_with?("\n") ? content : "#{content}\n"
    end

    def managed_block_pattern(kind, id)
      escaped_kind = Regexp.escape(kind)
      escaped_id = Regexp.escape(id)
      /^<!-- #{escaped_kind} #{escaped_id} -->\n.*?^<!-- \/#{escaped_kind} #{escaped_id} -->\n?/m
    end
  end
end
