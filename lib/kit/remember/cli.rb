# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Remember
  class CLI
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {
        json: false,
        dry_run: false,
        extracts_dir: DEFAULT_EXTRACTS_DIR,
        vault: ENV["KIT_VAULT"]
      }
    end

    def run
      parse_options!
      input = @argv.shift || "latest"
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      extract_path = resolve_input(input)
      extract = load_extract(extract_path)
      vault = resolve_vault
      plan = Planner.new(extract: extract, extract_path: extract_path, vault_dir: vault).plan
      result = Notebook.new(plan: plan, dry_run: @options[:dry_run]).apply

      if @options[:json]
        @out.puts JSON.pretty_generate(result)
      else
        Array(result["warnings"]).each { |warning| @err.puts "Warning: #{warning}" }
        action = @options[:dry_run] ? "plan" : "remember"
        @out.puts "OK (#{action}): #{result['slug']}"
        @out.puts "  vault: #{result['vault']}"
        result.fetch("files").each { |path| @out.puts "  note:  #{path}" }
      end
      0
    rescue Error => e
      @err.puts "Error: #{e.message}"
      1
    rescue OptionParser::ParseError => e
      @err.puts "Error: #{e.message}"
      1
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: kit remember [options] [INPUT]"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--dry-run", "Show planned writes without modifying notes") { @options[:dry_run] = true }
        opts.on("--vault DIR", "Durable notes root (default: KIT_VAULT or obsidian/)") do |dir|
          @options[:vault] = dir
        end
        opts.on("--extracts-dir DIR", "Extract root (default: extracts/)") do |dir|
          @options[:extracts_dir] = File.expand_path(dir)
        end
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
    end

    def resolve_input(input)
      value = input.to_s.strip
      raise Error, "missing INPUT" if value.empty?
      return latest_extract if value == "latest"
      raise Error, "remember v1 expects notice extract JSON; use extracts/json/<slug>.notice.json" unless value.end_with?(".json") || File.extname(value).empty?

      explicit = File.expand_path(value)
      return explicit if value.end_with?(".json")

      File.join(File.expand_path(@options[:extracts_dir]), "json", "#{value}.notice.json")
    end

    def latest_extract
      pattern = File.join(File.expand_path(@options[:extracts_dir]), "json", "*.notice.json")
      latest = Dir[pattern].max_by { |path| [File.mtime(path), path] }
      raise Error, "no notice extract JSON files found in #{File.dirname(pattern)}" unless latest

      latest
    end

    def resolve_vault
      value = @options[:vault].to_s.strip
      value.empty? ? DEFAULT_VAULT_DIR : File.expand_path(value)
    end

    def load_extract(path)
      raise Error, "notice extract JSON not found: #{path}" unless File.file?(path)

      payload = JSON.parse(File.read(path))
      raise Error, "notice extract JSON must be an object: #{path}" unless payload.is_a?(Hash)
      raise Error, "unsupported notice extract schema_version: #{payload['schema_version'].inspect}" unless payload["schema_version"] == 1
      raise Error, "unsupported notice extract kind: #{payload['kind'].inspect}" unless payload["kind"] == "kit_notice_extract"
      raise Error, "notice extract missing slug" if payload["slug"].to_s.strip.empty?
      raise Error, "notice extract missing items array" unless payload["items"].is_a?(Array)

      payload["items"].each_with_index do |item, index|
        raise Error, "item #{index} must be an object" unless item.is_a?(Hash)
        raise Error, "item #{index} missing id" if item["id"].to_s.strip.empty?
        raise Error, "item #{index} missing bucket" if item["bucket"].to_s.strip.empty?
        raise Error, "item #{index} missing text" if item["text"].to_s.strip.empty?
      end

      payload
    rescue JSON::ParserError => e
      raise Error, "invalid notice extract JSON at #{path}: #{e.message}"
    end
  end
end
