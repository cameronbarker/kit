# frozen_string_literal: true

module Kit::Surface
  class Parser
    MANAGED_BLOCK_PATTERN = /^<!-- kit:item ([^ ]+) -->\n(.*?)^<!-- \/kit:item \1 -->\n?/m
    CHECKBOX_PATTERN = /^\s*- \[([ xX])\] (.*)$/
    METADATA_PATTERN = /^\s+- ([^:]+):\s*(.*)$/

    attr_reader :vault_dir

    def initialize(vault_dir:)
      @vault_dir = File.expand_path(vault_dir)
    end

    def parse
      items = []
      warnings = []

      NOTE_PATHS.each do |parts|
        path = File.join(vault_dir, *parts)
        unless File.file?(path)
          warnings << "Missing note: #{relative_note_path(path)}"
          next
        end

        parsed = parse_note(path)
        items.concat(parsed.fetch("items"))
        warnings.concat(parsed.fetch("warnings"))
      end

      {
        "items" => items,
        "warnings" => warnings
      }
    end

    private

    def parse_note(path)
      content = File.read(path)
      items = []
      warnings = []
      content.scan(MANAGED_BLOCK_PATTERN) do |id, body|
        item = parse_block(id, body, path)
        if item
          items << item
        else
          warnings << "Could not parse item block #{id} in #{relative_note_path(path)}"
        end
      end

      {
        "items" => items,
        "warnings" => warnings
      }
    end

    def parse_block(id, body, path)
      lines = body.lines.map(&:chomp)
      task_line = lines.find { |line| line.match?(CHECKBOX_PATTERN) }
      return nil unless task_line

      match = task_line.match(CHECKBOX_PATTERN)
      checkbox = match[1]
      text, inline = split_inline_metadata(match[2])
      metadata = parse_metadata(lines)

      {
        "id" => id,
        "text" => text,
        "type" => metadata["Type"],
        "bucket" => metadata["Bucket"],
        "owner" => inline["owner"],
        "status" => inline["status"],
        "completion" => checked?(checkbox) ? "completed" : "open",
        "due_date" => due_date(metadata),
        "source" => inline["source"],
        "notice" => metadata["Notice"],
        "transcript" => metadata["Transcript"],
        "speaker" => metadata["Speaker"],
        "quote" => normalize_quote(metadata["Quote"]),
        "note_path" => path
      }
    end

    def split_inline_metadata(value)
      text = value.to_s.strip
      inline = {}
      if (match = text.match(/\A(.*)\s+_\((.*)\)_\s*\z/))
        text = match[1].strip
        inline = parse_inline(match[2])
      end

      [text, inline]
    end

    def parse_inline(value)
      status, rest = value.to_s.split(",", 2).map(&:to_s)
      inline = { "status" => status.empty? ? nil : status }
      rest.to_s.strip.scan(/(?:\A|,\s*)(owner|source):\s*(.*?)(?=,\s*(?:owner|source):|\z)/) do |key, raw|
        inline[key] = raw.strip
      end
      inline
    end

    def parse_metadata(lines)
      lines.each_with_object({}) do |line, metadata|
        match = line.match(METADATA_PATTERN)
        next unless match

        metadata[match[1].strip] = match[2].strip
      end
    end

    def normalize_quote(value)
      text = value.to_s
      return nil if text.empty?

      text.start_with?('"') && text.end_with?('"') ? text[1...-1].gsub('\"', '"') : text
    end

    def due_date(metadata)
      value = metadata["Due"] || metadata["Due Date"] || metadata["Due date"]
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def checked?(checkbox)
      checkbox.to_s.downcase == "x"
    end

    def relative_note_path(path)
      path.delete_prefix("#{vault_dir}/")
    end
  end
end
