# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Brief
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
        vault: ENV["KIT_VAULT"],
        me: ENV["KIT_ME"]
      }
    end

    def run
      parse_options!
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      vault = resolve_vault
      parsed = Kit::Surface::Parser.new(vault_dir: vault).parse
      payload = Report.new(
        vault_dir: vault,
        items: parsed.fetch("items"),
        warnings: parsed.fetch("warnings"),
        me: @options[:me]
      ).write

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
        opts.banner = "Usage: kit brief [options]"
        opts.separator ""
        opts.separator "Generate a thin leadership brief from Kit-managed durable notes."
        opts.separator ""
        opts.separator "Options:"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--vault DIR", "Durable notes root (default: KIT_VAULT or obsidian/)") do |dir|
          @options[:vault] = dir
        end
        opts.on("--me NAME", "Your owner name for waiting-on-me classification") do |name|
          @options[:me] = name
        end
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
    end

    def resolve_vault
      value = @options[:vault].to_s.strip
      value.empty? ? DEFAULT_VAULT_DIR : File.expand_path(value)
    end

    def render_human(payload)
      counts = payload.fetch("counts")
      @out.puts "Kit brief"
      @out.puts "  vault: #{payload['vault']}"
      @out.puts "  note:  #{payload['artifact_path']}"
      @out.puts "  moved: #{counts['what_moved']}  open: #{open_count(counts)}  decisions: #{counts['decisions_needed']}  loops: #{counts['open_loops']}  needs review: #{counts['needs_review']}"
      @out.puts

      render_section("What moved", payload.dig("sections", "what_moved"))
      render_section("Waiting on me", payload.dig("sections", "waiting_on_me"))
      render_section("Waiting on others", payload.dig("sections", "waiting_on_others"))
      render_section("Open commitments - unclassified", payload.dig("sections", "open_commitments_unclassified"))
      render_section("Decisions needed", payload.dig("sections", "decisions_needed"))
      render_section("Open loops", payload.dig("sections", "open_loops"))
      render_section("Needs review", payload.dig("sections", "needs_review"), review: true)
      render_actions(payload.dig("sections", "recommended_next_actions"))
      render_text("Stakeholder update draft", payload.dig("sections", "stakeholder_update_draft"))
      render_text("What changed since last week", payload.dig("sections", "insufficient_history"))
      render_text("Insufficient signal", payload.dig("sections", "insufficient_signal"))

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

    def render_actions(actions)
      actions = Array(actions)
      return if actions.empty?

      @out.puts "Recommended next actions:"
      actions.each do |action|
        @out.puts "  - #{action['text']} (id: #{action['item_id']})"
      end
      @out.puts
    end

    def render_text(title, values)
      values = Array(values)
      return if values.empty?

      @out.puts "#{title}:"
      values.each { |value| @out.puts "  - #{value}" }
      @out.puts
    end

    def open_count(counts)
      counts["waiting_on_me"] + counts["waiting_on_others"] + counts["open_commitments_unclassified"]
    end
  end
end
