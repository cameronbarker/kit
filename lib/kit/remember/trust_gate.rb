# frozen_string_literal: true

module Kit::Remember
  class TrustGate
    NOTE_PATHS = Planner::NOTE_BY_BUCKET.values.uniq.freeze
    MANAGED_BLOCK_PATTERN = /^<!-- kit:item ([^ ]+) -->\n(.*?)^<!-- \/kit:item \1 -->\n?/m
    INLINE_PATTERN = /^(\s*- \[[ xX]\] .*?_\()([^,\)]*)(.*\)_\s*)$/m
    CHECKBOX_PATTERN = /^\s*- \[([ xX])\] (.*)$/
    METADATA_PATTERN = /^\s+- ([^:]+):\s*(.*)$/

    attr_reader :vault_dir

    def initialize(vault_dir:)
      @vault_dir = File.expand_path(vault_dir)
    end

    def accept(ids)
      update_status(ids, "accepted", "accept")
    end

    def reject(ids)
      update_status(ids, "rejected", "reject")
    end

    def pending
      items = scan_items.select { |item| pending_item?(item) }
      {
        "schema_version" => 1,
        "kind" => "kit_remember_pending",
        "vault" => vault_dir,
        "count" => items.length,
        "items" => items
      }
    end

    private

    def update_status(ids, status, action)
      requested = ids.map { |id| clean_id(id) }.reject(&:empty?)
      raise Error, "missing item id" if requested.empty?

      requested_lookup = requested.each_with_object({}) { |id, lookup| lookup[id] = true }
      updated = []
      changed_files = []

      note_paths.each do |path|
        next unless File.file?(path)

        original = File.read(path)
        changed = false
        content = original.gsub(MANAGED_BLOCK_PATTERN) do |block|
          id = Regexp.last_match(1)
          unless requested_lookup[id]
            block
          else
            rewritten = rewrite_block_status(block, status)
            changed ||= rewritten != block
            updated << item_summary(id, rewritten, path).merge("previous_status" => current_status(block))
            requested_lookup.delete(id)
            rewritten
          end
        end

        next unless changed

        File.write(path, content)
        changed_files << path
      end

      {
        "schema_version" => 1,
        "kind" => "kit_remember_trust_update",
        "action" => action,
        "status" => status,
        "vault" => vault_dir,
        "requested_ids" => requested,
        "updated" => updated,
        "missing_ids" => requested_lookup.keys,
        "files" => changed_files.sort
      }
    end

    def rewrite_block_status(block, status)
      block.sub(INLINE_PATTERN) do
        "#{Regexp.last_match(1)}#{status}#{Regexp.last_match(3)}"
      end
    end

    def scan_items
      note_paths.flat_map do |path|
        next [] unless File.file?(path)

        File.read(path).scan(MANAGED_BLOCK_PATTERN).map do |id, body|
          item_summary(id, body, path)
        end
      end
    end

    def item_summary(id, block, path)
      lines = block.lines.map(&:chomp)
      task_line = lines.find { |line| line.match?(CHECKBOX_PATTERN) }
      checkbox = task_line&.match(CHECKBOX_PATTERN)
      metadata = parse_metadata(lines)

      {
        "id" => id,
        "text" => checkbox ? clean_task_text(checkbox[2]) : nil,
        "status" => current_status(block),
        "completion" => checkbox && checkbox[1].downcase == "x" ? "completed" : "open",
        "type" => metadata["Type"],
        "bucket" => metadata["Bucket"],
        "owner" => current_inline_value(block, "owner"),
        "source" => current_inline_value(block, "source"),
        "note_path" => path
      }
    end

    def pending_item?(item)
      status = item["status"].to_s.strip.downcase
      item["completion"] == "open" && !trusted_status?(status) && status != "rejected"
    end

    def current_status(block)
      match = block.match(INLINE_PATTERN)
      match && match[2].to_s.strip
    end

    def current_inline_value(block, key)
      match = block.match(/(?:\A|,\s*)#{Regexp.escape(key)}:\s*(.*?)(?=,\s*(?:owner|source):|\)_|\z)/m)
      match && match[1].to_s.strip
    end

    def trusted_status?(status)
      %w[accepted trusted confirmed actionable].include?(status)
    end

    def clean_task_text(value)
      value.to_s.sub(/\s+_\(.*\)_\s*\z/, "").strip
    end

    def parse_metadata(lines)
      lines.each_with_object({}) do |line, metadata|
        match = line.match(METADATA_PATTERN)
        next unless match

        metadata[match[1].strip] = match[2].strip
      end
    end

    def note_paths
      NOTE_PATHS.map { |parts| File.join(vault_dir, *parts) }
    end

    def clean_id(id)
      id.to_s.strip
    end
  end
end
