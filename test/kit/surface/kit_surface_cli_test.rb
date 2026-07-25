# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::SurfaceCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-surface-cli-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Commitments"))
    FileUtils.mkdir_p(File.join(@vault, "Open Loops"))
    FileUtils.mkdir_p(File.join(@vault, "Decisions"))
    write_notes
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_help_prints_usage
    result = run_kit("surface", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit surface [options]"
    assert_includes result[:stdout], "--vault DIR"
    assert_empty result[:stderr]
  end

  def test_surface_json_reads_temp_vault
    result = run_kit("surface", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:stderr]

    payload = JSON.parse(result[:stdout])
    assert_equal 1, payload["schema_version"]
    assert_equal "kit_surface", payload["kind"]
    assert_equal @vault, payload["vault"]
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_equal 4, payload.dig("counts", "open")
    assert_equal 1, payload.dig("counts", "completed")
    assert_equal 3, payload.dig("counts", "needs_review")
    assert_equal ["platform-sync-c001", "platform-sync-o001", "platform-sync-d001"], payload.dig("sections", "needs_review").map { |item| item["id"] }
    assert_equal ["platform-sync-c002"], payload.dig("sections", "waiting_on_others").map { |item| item["id"] }
  end

  def test_surface_human_marks_review_items
    result = run_kit("surface", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "Kit surface"
    assert_includes result[:stdout], "Needs review:"
    assert_includes result[:stdout], "[review] Follow up with Priya."
    assert_includes result[:stdout], "Waiting on others:"
    assert_includes result[:stdout], "Priya will update the API proposal."
  end

  def test_surface_uses_kit_vault_when_flag_absent
    result = run_kit_without_vault("surface", "--json", env: { "KIT_VAULT" => @vault })

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal @vault, payload["vault"]
    assert_equal 5, payload["items"].length
  end

  private

  def write_notes
    File.write(
      File.join(@vault, "Commitments", "Commitments.md"),
      <<~MD
        # Commitments

        <!-- kit:item platform-sync-c001 -->
        - [ ] Follow up with Priya. _(possible, owner: Cameron, source: Platform Sync @ 00:00:12)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
          - Transcript: /tmp/transcripts/json/platform-sync.json
          - Speaker: Cameron / SPEAKER_00
          - Quote: "I'll follow up with Priya."
        <!-- /kit:item platform-sync-c001 -->

        <!-- kit:item platform-sync-c002 -->
        - [ ] Priya will update the API proposal. _(accepted, owner: Priya, source: Platform Sync @ 00:01:01)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c002 -->

        <!-- kit:item platform-sync-c003 -->
        - [x] Send the rollout note. _(accepted, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c003 -->
      MD
    )

    File.write(
      File.join(@vault, "Open Loops", "Open Loops.md"),
      <<~MD
        # Open Loops

        <!-- kit:item platform-sync-o001 -->
        - [ ] Can someone own the migration comms? _(possible, owner: unknown, source: Platform Sync @ 00:03:00)_
          - Type: open_loop
          - Bucket: open_loops
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-o001 -->
      MD
    )

    File.write(
      File.join(@vault, "Decisions", "Decisions.md"),
      <<~MD
        # Decisions

        <!-- kit:item platform-sync-d001 -->
        - [ ] Keep the beta behind a feature flag. _(possible, owner: unknown, source: Platform Sync @ 00:04:00)_
          - Type: decision
          - Bucket: decisions
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-d001 -->
      MD
    )
  end

  def run_kit(*args, env: {})
    stdout, stderr, status = Open3.capture3(env, RUBY, File.join(ROOT, "bin/kit"), *args, "--vault", @vault, chdir: ROOT)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  def run_kit_without_vault(*args, env: {})
    stdout, stderr, status = Open3.capture3(env, RUBY, File.join(ROOT, "bin/kit"), *args, chdir: ROOT)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
