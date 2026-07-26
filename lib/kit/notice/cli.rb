# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Notice
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
        ai: false,
        retrieval: true,
        retrieval_query: nil,
        retrieval_mode: "query",
        collection: nil,
        limit: 5,
        me: ENV["KIT_ME"],
        transcripts_dir: DEFAULT_TRANSCRIPTS_DIR,
        extracts_dir: DEFAULT_EXTRACTS_DIR,
        out: nil
      }
    end

    def run
      parse_options!
      input = @argv.shift || "latest"
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      transcript_path = resolve_input(input)
      payload = load_transcript(transcript_path)
      extract = Extractor.new(payload: payload, transcript_path: transcript_path, me: @options[:me]).extract
      extract = enrich(extract, payload) if @options[:ai]
      result = Artifacts.new(payload: extract, extracts_dir: @options[:extracts_dir], out_path: @options[:out]).write!

      if @options[:json]
        @out.puts JSON.pretty_generate(result)
      else
        result.fetch("warnings", []).each { |warning| @err.puts "Warning: #{warning}" }
        @out.puts "OK (notice): #{result['slug']}"
        @out.puts "  json: #{result.dig('outputs', 'json')}"
        @out.puts "  md:   #{result.dig('outputs', 'md')}"
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
        opts.banner = "Usage: kit notice [options] [INPUT]"
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        opts.on("--ai", "Add opt-in AI enrichment (defaults to mock unless KIT_AI_PROVIDER is set)") { @options[:ai] = true }
        opts.on("--retrieval QUERY", "Override retrieval query/context") { |query| @options[:retrieval_query] = query }
        opts.on("--no-retrieval", "Run AI enrichment without qmd retrieval") { @options[:retrieval] = false }
        opts.on("--retrieval-mode MODE", "qmd retrieval mode: query or search") { |mode| @options[:retrieval_mode] = mode }
        opts.on("--collection NAME", "Restrict qmd retrieval to collection") { |name| @options[:collection] = name }
        opts.on("--limit N", Integer, "Maximum retrieval hits") { |limit| @options[:limit] = limit }
        opts.on("--me NAME", "Speaker name that represents you") { |name| @options[:me] = name }
        opts.on("--transcripts-dir DIR", "Transcript root (default: transcripts/)") do |dir|
          @options[:transcripts_dir] = File.expand_path(dir)
        end
        opts.on("--extracts-dir DIR", "Extract output root (default: extracts/)") do |dir|
          @options[:extracts_dir] = File.expand_path(dir)
        end
        opts.on("--out PATH", "Output base path, .json path, or .md path") { |path| @options[:out] = path }
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          exit 0
        end
      end
      parser.parse!(@argv)
      @options[:me] = @options[:me].to_s.strip
      @options[:me] = nil if @options[:me].empty?
    end

    def enrich(extract, payload)
      provider = Kit::AI.provider(ENV.fetch("KIT_AI_PROVIDER", "mock"))
      retrieval = Kit::Retrieval.new(
        mode: @options[:retrieval_mode],
        collection: @options[:collection],
        limit: @options[:limit]
      )
      Enrichment.new(
        extract: extract,
        transcript: payload,
        provider: provider,
        retrieval: retrieval,
        retrieval_enabled: @options[:retrieval],
        retrieval_query: @options[:retrieval_query]
      ).apply
    rescue Kit::AI::Error => e
      raise Error, e.message
    end

    def resolve_input(input)
      value = input.to_s.strip
      raise Error, "missing INPUT" if value.empty?
      return latest_transcript if value == "latest"
      raise Error, "notice v1 expects normalized transcript JSON; use transcripts/json/<slug>.json" if value.end_with?(".md")

      explicit = File.expand_path(value)
      return explicit if value.end_with?(".json")

      File.join(File.expand_path(@options[:transcripts_dir]), "json", "#{value}.json")
    end

    def latest_transcript
      pattern = File.join(File.expand_path(@options[:transcripts_dir]), "json", "*.json")
      latest = Dir[pattern].max_by { |path| [File.mtime(path), path] }
      raise Error, "no transcript JSON files found in #{File.dirname(pattern)}" unless latest

      latest
    end

    def load_transcript(path)
      raise Error, "transcript JSON not found: #{path}" unless File.file?(path)

      payload = JSON.parse(File.read(path))
      raise Error, "transcript JSON must be an object: #{path}" unless payload.is_a?(Hash)
      raise Error, "transcript JSON missing segments array: #{path}" unless payload["segments"].is_a?(Array)

      payload["segments"].each_with_index do |segment, index|
        raise Error, "segment #{index} must be an object" unless segment.is_a?(Hash)
        raise Error, "segment #{index} missing text" unless segment.key?("text")
      end

      payload
    rescue JSON::ParserError => e
      raise Error, "invalid transcript JSON at #{path}: #{e.message}"
    end
  end
end
