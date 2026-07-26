# frozen_string_literal: true

require "json"
require "minitest/autorun"

require_relative "../../lib/kit"

class KitRetrievalTest < Minitest::Test
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  def test_normalizes_array_fixture
    client = fixture_client("query_platform_sync.json")
    payload = Kit::Retrieval.new(client: client, limit: 2).retrieve("api proposal")

    assert_equal true, payload["available"]
    assert_equal "query", payload["mode"]
    hit = payload["hits"].first
    assert_equal "test/fixtures/qmd_corpus/transcripts/platform-sync.md", hit["path"]
    assert_equal "platform-sync", hit["docid"]
    assert_equal "transcripts", hit["collection"]
    assert_equal 0.87, hit["score"]
    assert_includes hit["snippet"], "Cameron will follow up"
  end

  def test_normalizes_results_hash_fixture
    client = fixture_client("search_priya.json")
    payload = Kit::Retrieval.new(client: client, mode: "search").retrieve("Priya")

    hit = payload["hits"].first
    assert_equal "test/fixtures/qmd_corpus/transcripts/platform-sync.md", hit["path"]
    assert_equal "platform-sync#priya", hit["docid"]
    assert_equal "transcripts", hit["collection"]
    assert_equal 0.64, hit["score"]
    assert_includes hit["snippet"], "Priya asked"
  end

  def test_degrades_when_qmd_is_unavailable
    client = Object.new
    def client.query(*)
      raise Kit::Qmd::MissingBinaryError, "missing qmd"
    end

    payload = Kit::Retrieval.new(client: client).retrieve("api")

    assert_equal false, payload["available"]
    assert_empty payload["hits"]
    assert_includes payload["warnings"], "missing qmd"
  end

  private

  def fixture_client(name)
    json = JSON.parse(File.read(File.expand_path("../fixtures/qmd/#{name}", __dir__)))
    status = Status.new(0)
    result = Kit::Qmd::Client::Result.new(success?: true, argv: ["qmd"], stdout: "", stderr: "", status: status, json: json)
    Object.new.tap do |client|
      client.define_singleton_method(:query) { |*| result }
      client.define_singleton_method(:search) { |*| result }
    end
  end
end
