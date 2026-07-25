# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Followup
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
        me: ENV["KIT_ME"],
        overdue: false,
        waiting_on_me_only: false,
        waiting_on_others_only: false
      }
    end

    def run
      parse_options!
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      parsed = Kit::Surface::Parser.new(vault_dir: resolve_vault).parse
      report = Report.new(
        vault_dir: resolve_vault,
        items: parsed.fetch("items"),
        warnings: parsed.fetch("warnings"),
        me: @options[:me],
        overdue: @options[:overdue],
        waiting_on_me_only: @options[:waiting_on_me_only],
        waiting_on_others_only: @options[:waiting_on_others_only]
      ).to_h

      if @options[:json]
        @out.puts JSON.pretty_generate(report)
      else
        render_human(report)
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
        opts.banner = "Usage: kit followup [options]"
        opts.separator ""
        opts.separator "Track promises, waiting-on items, and stale commitment candidates."
        opts.separator ""
        opts.separator "Options:"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--vault DIR", "Durable notes root (default: KIT_VAULT or obsidian/)") do |dir|
          @options[:vault] = dir
        end
        opts.on("--me NAME", "Your owner name for waiting-on-me classification") do |name|
          @options[:me] = name
        end
        opts.on("--overdue", "Show no-due-date/stale accepted commitment candidates") do
          @options[:overdue] = true
        end
        opts.on("--waiting-on-me", "Show accepted open commitments you made") do
          @options[:waiting_on_me_only] = true
        end
        opts.on("--waiting-on-others", "Show accepted open commitments others made") do
          @options[:waiting_on_others_only] = true
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

    def render_human(report)
      counts = report.fetch("counts")
      @out.puts "Kit followup"
      @out.puts "  vault: #{report['vault']}"
      @out.puts "  waiting on me: #{counts['waiting_on_me']}  waiting on others: #{counts['waiting_on_others']}  no due date: #{counts['needs_renegotiation']}  needs review: #{counts['needs_review']}"
      @out.puts "  overdue: no-due-date/stale candidates in v1" if report.dig("filters", "overdue")
      @out.puts

      render_section("Waiting on me", report.dig("sections", "waiting_on_me"))
      render_section("Waiting on others", report.dig("sections", "waiting_on_others"))
      render_section("Needs renegotiation / no due date", report.dig("sections", "needs_renegotiation"))
      render_section("Needs review", report.dig("sections", "needs_review"), review: true)

      Array(report["warnings"]).each { |warning| @err.puts "Warning: #{warning}" }
    end

    def render_section(title, items, review: false)
      items = Array(items)
      return if items.empty?

      @out.puts "#{title}:"
      items.each do |item|
        marker = review ? "[review] " : ""
        owner = item["owner"].to_s.empty? ? "unknown" : item["owner"]
        source = item["source"].to_s.empty? ? item["note_path"] : item["source"]
        reason = item["followup_reason"].to_s.empty? ? "open" : item["followup_reason"].tr("_", " ")
        @out.puts "  - #{marker}#{item['text']} (id: #{item['id']}; owner: #{owner}; reason: #{reason}; source: #{source})"
        @out.puts "    #{item['nudge']}" unless review || item["nudge"].to_s.empty?
      end
      @out.puts
    end
  end
end
