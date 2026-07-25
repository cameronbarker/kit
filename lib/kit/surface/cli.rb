# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Surface
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
        needs_review_only: false
      }
    end

    def run
      parse_options!
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      vault = resolve_vault
      parsed = Parser.new(vault_dir: vault).parse
      report = Report.new(
        vault_dir: vault,
        items: parsed.fetch("items"),
        warnings: parsed.fetch("warnings"),
        me: @options[:me],
        needs_review_only: @options[:needs_review_only]
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
        opts.banner = "Usage: kit surface [options]"
        opts.separator ""
        opts.separator "Show the daily attention list from Kit-managed durable notes."
        opts.separator ""
        opts.separator "Options:"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--vault DIR", "Durable notes root (default: KIT_VAULT or obsidian/)") do |dir|
          @options[:vault] = dir
        end
        opts.on("--me NAME", "Your owner name for \"I said I would\" filtering/highlighting") do |name|
          @options[:me] = name
        end
        opts.on("--needs-review-only", "Show only possible/uncertain items") do
          @options[:needs_review_only] = true
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
      @out.puts "Kit surface"
      @out.puts "  vault: #{report['vault']}"
      @out.puts "  open: #{counts['open']}  needs review: #{counts['needs_review']}  completed: #{counts['completed']}"
      @out.puts

      render_section("Needs review", report.dig("sections", "needs_review"), review: true)
      render_section("I said I would", report.dig("sections", "i_made"))
      render_section("Waiting on others", report.dig("sections", "waiting_on_others"))
      render_section("Open loops", report.dig("sections", "open_loops"))
      render_section("Recent decisions", report.dig("sections", "recent_decisions"))

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
        @out.puts "  - #{marker}#{item['text']} (owner: #{owner}; source: #{source})"
      end
      @out.puts
    end
  end
end
