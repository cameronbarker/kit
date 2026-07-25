# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Prepare
  class CLI
    NEXT_UNIMPLEMENTED = "kit prepare --next is planned but not implemented yet. Use kit prepare --person NAME."

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {
        json: false,
        vault: ENV["KIT_VAULT"],
        me: ENV["KIT_ME"],
        person: nil,
        next: false
      }
    end

    def run
      parse_options!
      return run_next if @options[:next]

      person = resolve_person
      payload = Pack.new(vault_dir: resolve_vault, person: person, me: @options[:me]).write

      if @options[:json]
        @out.puts JSON.pretty_generate(payload)
      else
        render_human(payload)
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
        opts.banner = "Usage: kit prepare [options] [PERSON]"
        opts.separator ""
        opts.separator "Build a thin context pack before a 1:1."
        opts.separator ""
        opts.separator "Options:"
        opts.on("--person NAME", "Person to prepare for") { |name| @options[:person] = name }
        opts.on("--next", "Reserved for next-meeting prep; not implemented in v1") { @options[:next] = true }
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--vault DIR", "Durable notes root (default: KIT_VAULT or obsidian/)") do |dir|
          @options[:vault] = dir
        end
        opts.on("--me NAME", "Your owner name for future filtering/context") do |name|
          @options[:me] = name
        end
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
    end

    def run_next
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      if @options[:json]
        @out.puts JSON.pretty_generate(
          {
            "schema_version" => 1,
            "kind" => "kit_prepare_unimplemented",
            "command" => ["kit", "prepare", "--next"],
            "implemented" => false,
            "message" => NEXT_UNIMPLEMENTED
          }
        )
      else
        @err.puts NEXT_UNIMPLEMENTED
      end
      2
    end

    def resolve_person
      positional = @argv.dup
      raise Error, "unexpected arguments: #{positional.join(' ')}" if positional.length > 1

      flag_person = clean(@options[:person])
      arg_person = clean(positional.first)

      if flag_person && arg_person && !flag_person.casecmp?(arg_person)
        raise Error, "--person and PERSON disagree"
      end

      person = flag_person || arg_person
      raise Error, "missing person; use kit prepare --person NAME" if person.nil?

      person
    end

    def resolve_vault
      value = @options[:vault].to_s.strip
      value.empty? ? DEFAULT_VAULT_DIR : File.expand_path(value)
    end

    def render_human(payload)
      counts = payload.fetch("counts")
      @out.puts "Kit prepare: #{payload.dig('filters', 'person')}"
      @out.puts "  vault: #{payload['vault']}"
      @out.puts "  note:  #{payload['artifact_path']}"
      @out.puts "  commitments: #{counts['commitments']}  open loops: #{counts['open_loops']}  decisions: #{counts['decisions']}  needs review: #{counts['needs_review']}"
      @out.puts

      render_section("Open commitments", payload.dig("sections", "commitments"))
      render_section("Open loops", payload.dig("sections", "open_loops"))
      render_section("Recent related decisions", payload.dig("sections", "recent_decisions"))
      render_section("Needs review", payload.dig("sections", "needs_review"), review: true)

      Array(payload["warnings"]).each { |warning| @err.puts "Warning: #{warning}" }
    end

    def render_section(title, items, review: false)
      items = Array(items)
      return if items.empty?

      @out.puts "#{title}:"
      items.each do |item|
        marker = review ? "[review] " : ""
        owner = item["owner"].to_s.empty? ? "unknown" : item["owner"]
        source = item["source"].to_s.empty? ? item["note_path"] : item["source"]
        @out.puts "  - #{marker}#{item['text']} (id: #{item['id']}; owner: #{owner}; source: #{source})"
      end
      @out.puts
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
