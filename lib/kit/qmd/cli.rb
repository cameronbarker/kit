# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Qmd
  class CLI
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv, out: $stdout, err: $stderr, client: nil)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {
        json: false,
        collection: nil,
        limit: nil,
        embed: false
      }
      @client = client
    end

    def run
      command = @argv.shift
      case command
      when nil, "help", "-h", "--help"
        print_help
        0
      when "status"
        parse_common_options!
        wrap_result(client.status, "status")
      when "setup"
        parse_setup_options!
        run_setup
      when "update"
        parse_common_options!
        wrap_result(client.update, "update")
      when "query"
        run_search_like("query")
      when "search"
        run_search_like("search")
      else
        raise Error, "unknown qmd command: #{command}"
      end
    rescue MissingBinaryError, Error => e
      if @options[:json]
        @out.puts JSON.pretty_generate(error_payload(e.message))
      else
        @err.puts "Error: #{e.message}"
      end
      1
    rescue OptionParser::ParseError => e
      @err.puts "Error: #{e.message}"
      1
    end

    private

    def client
      @client ||= Client.new
    end

    def parse_common_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: kit qmd #{@command || 'COMMAND'} [options]"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("-h", "--help", "Show help") do
          print_help
          exit 0
        end
      end
      parser.parse!(@argv)
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?
    end

    def parse_setup_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: kit qmd setup [options]"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--embed", "Run qmd embed after update") { @options[:embed] = true }
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?
    end

    def run_search_like(command)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: kit qmd #{command} [options] QUERY"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--collection NAME", "Restrict to collection") { |name| @options[:collection] = name }
        opts.on("--limit N", Integer, "Maximum results") { |n| @options[:limit] = n }
        opts.on("-n N", Integer, "Maximum results") { |n| @options[:limit] = n }
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
      query = @argv.join(" ").strip
      raise Error, "missing QUERY" if query.empty?

      result = client.public_send(command, query, collection: @options[:collection], limit: @options[:limit], json: true)
      if @options[:json]
        @out.puts JSON.pretty_generate(success_payload(command, result).merge("results" => result.json || []))
      else
        @out.print result.stdout
      end
      result.success? ? 0 : 1
    end

    def run_setup
      added = []
      skipped = []
      DEFAULT_COLLECTIONS.each do |name, path|
        expanded = File.expand_path(path)
        unless Dir.exist?(expanded)
          skipped << { "name" => name, "path" => expanded, "reason" => "missing directory" }
          next
        end

        result = client.collection_add(path: expanded, name: name)
        entry = { "name" => name, "path" => expanded, "success" => result.success?, "stderr" => result.stderr.to_s.strip }
        added << entry
      end

      update_result = client.update
      embed_result = @options[:embed] ? client.embed : nil
      payload = {
        "schema_version" => 1,
        "kind" => "kit_qmd_setup",
        "implemented" => true,
        "collections" => {
          "added" => added,
          "skipped" => skipped
        },
        "update" => command_payload(update_result),
        "embed" => embed_result && command_payload(embed_result)
      }

      if @options[:json]
        @out.puts JSON.pretty_generate(payload)
      else
        @out.puts "Kit qmd setup"
        added.each { |entry| @out.puts "  #{entry['success'] ? 'added' : 'failed'} #{entry['name']}: #{entry['path']}" }
        skipped.each { |entry| @out.puts "  skipped #{entry['name']}: #{entry['path']} (#{entry['reason']})" }
        @out.puts "  update: #{update_result.success? ? 'ok' : 'failed'}"
        @out.puts "  embed:  #{embed_result.success? ? 'ok' : 'skipped'}" if embed_result
      end
      update_result.success? ? 0 : 1
    end

    def wrap_result(result, command)
      if @options[:json]
        @out.puts JSON.pretty_generate(success_payload(command, result))
      else
        @out.print result.stdout
        @err.print result.stderr
      end
      result.success? ? 0 : 1
    end

    def success_payload(command, result)
      {
        "schema_version" => 1,
        "kind" => "kit_qmd_#{command}",
        "implemented" => true,
        "qmd" => command_payload(result)
      }
    end

    def command_payload(result)
      {
        "command" => result.argv,
        "success" => result.success?,
        "exit_status" => result.status.exitstatus,
        "stdout" => result.stdout.to_s,
        "stderr" => result.stderr.to_s
      }
    end

    def error_payload(message)
      {
        "schema_version" => 1,
        "kind" => "kit_qmd_error",
        "implemented" => true,
        "error" => message
      }
    end

    def print_help
      @out.puts <<~HELP
        Usage: kit qmd COMMAND [options]

        Manage/search the local qmd index.

        Commands:
          status              Show qmd index status
          setup               Add Kit corpus collections and update
          update              Re-index configured collections
          query QUERY         Hybrid qmd query
          search QUERY        Keyword qmd search

        Options:
          --json              Emit machine-readable JSON
      HELP
    end
  end
end
