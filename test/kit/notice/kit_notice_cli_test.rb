# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::NoticeCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-notice-test-")
    @transcripts_dir = File.join(@tmpdir, "transcripts")
    @extracts_dir = File.join(@tmpdir, "extracts")
    FileUtils.mkdir_p(File.join(@transcripts_dir, "json"))
    write_transcript("platform-sync", title: "Platform Sync")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_help_prints_usage
    result = run_kit("notice", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit notice [options] [INPUT]"
    assert_empty result[:stderr]
  end

  def test_notice_accepts_slug_and_writes_artifacts
    result = run_kit("notice", "--me", "Cameron", "platform-sync")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "OK (notice): platform-sync"
    assert_empty result[:stderr]
    assert File.file?(File.join(@extracts_dir, "json", "platform-sync.notice.json"))
    assert File.file?(File.join(@extracts_dir, "md", "platform-sync.notice.md"))
  end

  def test_notice_json_accepts_explicit_path
    path = File.join(@transcripts_dir, "json", "platform-sync.json")
    result = run_kit("notice", "--json", "--me", "Cameron", path)

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "kit_notice_extract", payload["kind"]
    assert_equal "platform-sync", payload["slug"]
    assert_equal "commitments_i_made", payload["items"][0]["bucket"]
    assert File.file?(payload.dig("outputs", "json"))
  end

  def test_notice_without_ai_keeps_existing_payload_unenriched
    path = File.join(@transcripts_dir, "json", "platform-sync.json")
    result = run_kit("notice", "--json", "--me", "Cameron", path)

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    refute payload.key?("enrichment")
    assert payload["items"].all? { |item| !item.key?("enrichment") }
  end

  def test_notice_ai_json_adds_mock_draft_without_retrieval
    path = File.join(@transcripts_dir, "json", "platform-sync.json")
    result = run_kit("notice", "--json", "--ai", "--no-retrieval", "--me", "Cameron", path, env: { "KIT_AI_PROVIDER" => "mock" })

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal true, payload.dig("enrichment", "enabled")
    assert_equal "mock", payload.dig("enrichment", "provider")
    assert_equal false, payload.dig("enrichment", "retrieval", "available")
    assert_equal 2, payload.dig("enrichment", "counts", "deterministic_items")
    assert_equal 1, payload.dig("enrichment", "counts", "ai_items")
    ai_item = payload["items"].find { |item| item["enrichment"] == "ai" }
    assert_equal "possible", ai_item["status"]
    assert_includes ai_item["text"], "AI draft:"
    assert_equal [ai_item["citation"]], ai_item["citations"]
    markdown = File.read(payload.dig("outputs", "md"))
    assert_includes markdown, "[AI draft]"
  end

  def test_notice_ai_reports_unsupported_provider
    path = File.join(@transcripts_dir, "json", "platform-sync.json")
    result = run_kit("notice", "--json", "--ai", "--me", "Cameron", path, env: { "KIT_AI_PROVIDER" => "network" })

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "unsupported KIT_AI_PROVIDER"
  end

  def test_notice_defaults_to_latest
    write_transcript("newer", title: "Newer")
    newer = File.join(@transcripts_dir, "json", "newer.json")
    File.utime(Time.now + 5, Time.now + 5, newer)

    result = run_kit("notice", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "newer", payload["slug"]
  end

  def test_notice_warns_without_identity
    result = run_kit("notice", "platform-sync")

    assert_equal 0, result[:status]
    assert_includes result[:stderr], "Warning: No --me or KIT_ME supplied"
    markdown = File.read(File.join(@extracts_dir, "md", "platform-sync.notice.md"))
    assert_includes markdown, "## Commitments Needing Review"
  end

  def test_notice_rejects_markdown_input
    result = run_kit("notice", File.join(@transcripts_dir, "md", "platform-sync.md"))

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "notice v1 expects normalized transcript JSON"
  end

  def test_notice_rejects_invalid_json_shape
    bad = File.join(@transcripts_dir, "json", "bad.json")
    File.write(bad, "{}\n")

    result = run_kit("notice", bad)

    assert_equal 1, result[:status]
    assert_includes result[:stderr], "missing segments array"
  end

  private

  def write_transcript(slug, title:)
    File.write(
      File.join(@transcripts_dir, "json", "#{slug}.json"),
      JSON.pretty_generate(
        {
          "title" => title,
          "source_file" => "/tmp/#{slug}.m4a",
          "generated_at" => "2026-07-24T12:00:00Z",
          "segments" => [
            {
              "speaker" => "Cameron",
              "raw_speaker" => "SPEAKER_00",
              "start" => 12.3,
              "end" => 18.1,
              "text" => "I'll follow up with Priya."
            },
            {
              "speaker" => "Priya",
              "raw_speaker" => "SPEAKER_01",
              "start" => 61.0,
              "end" => 70.0,
              "text" => "I'll update the API proposal."
            }
          ]
        }
      ) + "\n"
    )
  end

  def run_kit(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      env,
      RUBY,
      File.join(ROOT, "bin/kit"),
      *args,
      "--transcripts-dir",
      @transcripts_dir,
      "--extracts-dir",
      @extracts_dir,
      chdir: ROOT
    )
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
