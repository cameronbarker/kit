# frozen_string_literal: true

require "json"
require "minitest/autorun"

require_relative "../../lib/kit"

class KitQmdClientTest < Minitest::Test
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  def test_query_builds_json_command_and_parses_output
    captured = []
    runner = lambda do |argv|
      captured << argv
      [File.read(fixture("query_platform_sync.json")), "", Status.new(0)]
    end

    client = Kit::Qmd::Client.new(binary: "qmd", index: "kit-test", runner: runner)
    result = client.query("api proposal", collection: "transcripts", limit: 2)

    assert result.success?
    assert_equal ["qmd", "query", "--index", "kit-test", "--json", "--collection", "transcripts", "-n", "2", "api proposal"], captured.first
    assert_equal 2, result.json.length
    assert_equal "platform-sync", result.json.first["docid"]
  end

  def test_invalid_json_is_reported
    runner = ->(_argv) { ["not json", "", Status.new(0)] }
    client = Kit::Qmd::Client.new(runner: runner)

    error = assert_raises(Kit::Qmd::Error) do
      client.search("api")
    end

    assert_includes error.message, "qmd returned invalid JSON"
  end

  def test_missing_binary_is_reported
    runner = ->(_argv) { raise Errno::ENOENT }
    client = Kit::Qmd::Client.new(runner: runner)

    error = assert_raises(Kit::Qmd::MissingBinaryError) do
      client.status
    end

    assert_includes error.message, "qmd binary not found"
  end

  private

  def fixture(name)
    File.expand_path("../fixtures/qmd/#{name}", __dir__)
  end
end
