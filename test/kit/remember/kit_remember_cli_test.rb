# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::RememberCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-remember-cli-test-")
    @extracts_dir = File.join(@tmpdir, "extracts")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@extracts_dir, "json"))
    write_extract("platform-sync", title: "Platform Sync")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_help_prints_usage
    result = run_kit("remember", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit remember [options] [INPUT]"
    assert_empty result[:stderr]
  end

  def test_remember_accepts_slug_and_writes_notes
    result = run_kit("remember", "platform-sync")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "OK (remember): platform-sync"
    assert File.file?(File.join(@vault, "Commitments", "Commitments.md"))
    assert File.file?(File.join(@vault, "Inbox", "Kit Inbox.md"))
  end

  def test_remember_json_accepts_explicit_path
    path = File.join(@extracts_dir, "json", "platform-sync.notice.json")
    result = run_kit("remember", "--json", path)

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "platform-sync", payload["slug"]
    assert_equal @vault, payload["vault"]
    assert_equal 2, payload["item_count"]
    assert_includes payload["files"], File.join(@vault, "Commitments", "Commitments.md")
  end

  def test_remember_defaults_to_latest
    write_extract("newer", title: "Newer")
    newer = File.join(@extracts_dir, "json", "newer.notice.json")
    File.utime(Time.now + 5, Time.now + 5, newer)

    result = run_kit("remember", "--json")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "newer", payload["slug"]
  end

  def test_remember_uses_kit_vault_when_flag_absent
    env_vault = File.join(@tmpdir, "env-vault")
    result = run_kit_without_vault("remember", "platform-sync", env: { "KIT_VAULT" => env_vault })

    assert_equal 0, result[:status], result[:stderr]
    assert File.file?(File.join(env_vault, "Commitments", "Commitments.md"))
  end

  def test_remember_defaults_to_repo_obsidian_vault
    result = run_kit_without_vault("remember", "--json", "--dry-run", "platform-sync")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal File.join(ROOT, "obsidian"), payload["vault"]
    assert_equal true, payload["dry_run"]
  end

  def test_dry_run_writes_no_files
    result = run_kit("remember", "--json", "--dry-run", "platform-sync")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal true, payload["dry_run"]
    refute File.exist?(File.join(@vault, "Commitments", "Commitments.md"))
  end

  def test_invalid_kind_fails_cleanly
    bad = File.join(@extracts_dir, "json", "bad.notice.json")
    File.write(bad, JSON.pretty_generate("schema_version" => 1, "kind" => "other", "slug" => "bad", "items" => []) + "\n")

    result = run_kit("remember", bad)

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "unsupported notice extract kind"
  end

  private

  def write_extract(slug, title:)
    File.write(
      File.join(@extracts_dir, "json", "#{slug}.notice.json"),
      JSON.pretty_generate(
        {
          "schema_version" => 1,
          "kind" => "kit_notice_extract",
          "title" => title,
          "slug" => slug,
          "generated_at" => "2026-07-25T12:00:00Z",
          "review_required" => true,
          "warnings" => [],
          "input" => {
            "transcript_json" => "/tmp/transcripts/json/#{slug}.json",
            "source_file" => "/tmp/#{slug}.m4a"
          },
          "items" => [
            item("#{slug}-c001", "commitment", "commitments_i_made", "Follow up with Priya.", "Cameron"),
            item("#{slug}-d001", "decision", "decisions", "Keep the beta behind a feature flag.", nil)
          ]
        }
      ) + "\n"
    )
  end

  def item(id, type, bucket, text, owner)
    {
      "id" => id,
      "type" => type,
      "bucket" => bucket,
      "text" => text,
      "owner" => owner,
      "status" => "possible",
      "citation" => {
        "transcript_path" => "/tmp/transcripts/json/platform-sync.json",
        "speaker" => owner || "Priya",
        "raw_speaker" => "SPEAKER_00",
        "timestamp" => "00:00:12",
        "quote" => text
      }
    }
  end

  def run_kit(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      env,
      RUBY,
      File.join(ROOT, "bin/kit"),
      *args,
      "--extracts-dir",
      @extracts_dir,
      "--vault",
      @vault,
      chdir: ROOT
    )
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  def run_kit_without_vault(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      env,
      RUBY,
      File.join(ROOT, "bin/kit"),
      *args,
      "--extracts-dir",
      @extracts_dir,
      chdir: ROOT
    )
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
