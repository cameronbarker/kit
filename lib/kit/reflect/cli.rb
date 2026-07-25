# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Reflect
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
        opts.banner = "Usage: kit reflect [options]"
        opts.separator ""
        opts.separator "Generate a thin weekly reflection from Kit-managed durable notes."
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
      @out.puts "Kit reflect"
      @out.puts "  vault: #{payload['vault']}"
      @out.puts "  note:  #{payload['artifact_path']}"
      @out.puts "  open commitments: #{counts['trusted_open_commitments']}  completed: #{counts['trusted_completed_commitments']}  no due date: #{counts['no_due_date_commitments']}  decisions: #{counts['open_decisions']}  loops: #{counts['open_loops']}  needs review: #{counts['needs_review']}"
      @out.puts

      render_text("Follow-through snapshot", payload.dig("sections", "follow_through_snapshot"))
      render_section("What keeps slipping", payload.dig("sections", "what_keeps_slipping"))
      render_load(payload.dig("sections", "commitment_load"))
      render_section("Decision bottlenecks", payload.dig("sections", "decision_bottlenecks"))
      render_section("Open-loop pressure", payload.dig("sections", "open_loop_pressure"))
      render_section("Needs review backlog", payload.dig("sections", "needs_review_backlog"), review: true)
      render_brief_history(payload["brief_history"])
      render_text("Insufficient signal", payload.dig("sections", "insufficient_signal"))

      Array(payload["warnings"]).each { |warning| @err.puts "Warning: #{warning}" }
    end

    def render_load(load)
      load ||= {}
      render_section("Commitment load - waiting on me", load["waiting_on_me"])
      render_section("Commitment load - waiting on others", load["waiting_on_others"])
      render_section("Commitment load - unclassified", load["unclassified"])
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

    def render_text(title, values)
      values = Array(values)
      return if values.empty?

      @out.puts "#{title}:"
      values.each { |value| @out.puts "  - #{value}" }
      @out.puts
    end

    def render_brief_history(history)
      history ||= {}
      @out.puts "Brief history:"
      @out.puts "  - weekly briefs found: #{history['count'].to_i}"
      if history["first_date"] && history["latest_date"]
        @out.puts "  - date range: #{history['first_date']} to #{history['latest_date']}"
      else
        @out.puts "  - date range: none found"
      end
      @out.puts
    end
  end
end
