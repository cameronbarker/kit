# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

module Kit::Qmd
  class Client
    Result = Struct.new(:success?, :argv, :stdout, :stderr, :status, :json, keyword_init: true)

    attr_reader :binary, :index, :runner

    def initialize(binary: ENV.fetch("KIT_QMD_BINARY", DEFAULT_BINARY), index: ENV.fetch("KIT_QMD_INDEX", DEFAULT_INDEX), runner: nil)
      @binary = binary.to_s.strip.empty? ? DEFAULT_BINARY : binary
      @index = index.to_s.strip.empty? ? nil : index
      @runner = runner || method(:default_runner)
    end

    def status(json: false)
      run_jsonless(["status"], json: json)
    end

    def collection_list(json: false)
      run_jsonless(["collection", "list"], json: json)
    end

    def collection_add(path:, name:)
      run_jsonless(["collection", "add", path, "--name", name])
    end

    def update
      run_jsonless(["update"])
    end

    def embed
      run_jsonless(["embed"])
    end

    def query(text, collection: nil, limit: nil, json: true)
      search_command("query", text, collection: collection, limit: limit, json: json)
    end

    def search(text, collection: nil, limit: nil, json: true)
      search_command("search", text, collection: collection, limit: limit, json: json)
    end

    def available?
      _stdout, _stderr, status = runner.call(["which", binary])
      status.success?
    rescue Errno::ENOENT
      false
    end

    private

    def search_command(command, text, collection:, limit:, json:)
      raise Error, "missing query" if text.to_s.strip.empty?

      args = [command]
      args.concat(["--index", index]) if index
      args.concat(["--json"]) if json
      args.concat(["--collection", collection.to_s]) if collection && !collection.to_s.strip.empty?
      args.concat(["-n", limit.to_i.to_s]) if limit && limit.to_i.positive?
      args << text.to_s
      run(args, parse_json: json)
    end

    def run_jsonless(args, json: false)
      full = args.dup
      full.concat(["--index", index]) if index && !collection_management?(args)
      full << "--json" if json
      run(full, parse_json: json)
    end

    def run(args, parse_json: false)
      argv = [binary, *args]
      stdout, stderr, status = runner.call(argv)
      parsed = parse_json_payload(stdout, argv) if parse_json && status.success?
      Result.new(success?: status.success?, argv: argv, stdout: stdout, stderr: stderr, status: status, json: parsed)
    rescue Errno::ENOENT
      raise MissingBinaryError, "qmd binary not found on PATH; install @tobilu/qmd or set KIT_QMD_BINARY"
    end

    def parse_json_payload(stdout, argv)
      text = stdout.to_s.strip
      return [] if text.empty?

      JSON.parse(text)
    rescue JSON::ParserError => e
      raise Error, "qmd returned invalid JSON for #{argv.shelljoin}: #{e.message}"
    end

    def collection_management?(args)
      args.first == "collection"
    end

    def default_runner(argv)
      Open3.capture3(*argv)
    end
  end
end
