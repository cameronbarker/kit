# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::RememberTrustGateTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-remember-trust-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Commitments"))
    write_commitments
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_accept_updates_only_inline_status
    result = Kit::Remember::TrustGate.new(vault_dir: @vault).accept(["platform-sync-c001"])

    assert_equal "accept", result["action"]
    assert_equal ["platform-sync-c001"], result["updated"].map { |item| item["id"] }
    assert_empty result["missing_ids"]

    content = File.read(commitments_path)
    assert_includes content, "- [ ] Follow up with Priya. _(accepted, owner: Cameron, source: Platform Sync @ 00:00:12)_"
    assert_includes content, "  - Quote: \"I'll follow up with Priya.\""
    assert_includes content, "- [x] Send the rollout note. _(possible, owner: Cameron, source: Platform Sync @ 00:02:00)_"
  end

  def test_accept_makes_open_item_actionable_in_surface_without_checking_it
    Kit::Remember::TrustGate.new(vault_dir: @vault).accept(["platform-sync-c001"])

    parsed = Kit::Surface::Parser.new(vault_dir: @vault).parse
    report = Kit::Surface::Report.new(vault_dir: @vault, items: parsed["items"], warnings: [], me: "Cameron").to_h

    assert_equal ["platform-sync-c001"], report.dig("sections", "i_made").map { |item| item["id"] }
    assert_equal "open", report.dig("sections", "i_made", 0, "completion")
    assert_equal 1, report.dig("counts", "completed")
  end

  def test_reject_updates_status_and_surface_ignores_it
    Kit::Remember::TrustGate.new(vault_dir: @vault).reject(["platform-sync-c001"])

    parsed = Kit::Surface::Parser.new(vault_dir: @vault).parse
    report = Kit::Surface::Report.new(vault_dir: @vault, items: parsed["items"], warnings: [], me: "Cameron").to_h

    rejected = report["items"].find { |item| item["id"] == "platform-sync-c001" }
    assert_equal "rejected", rejected["status"]
    assert_equal true, rejected["rejected"]
    refute_includes report.dig("sections", "needs_review").map { |item| item["id"] }, "platform-sync-c001"
    assert_empty report.dig("sections", "i_made")
    assert_equal 1, report.dig("counts", "open")
  end

  def test_pending_lists_open_untrusted_items
    Kit::Remember::TrustGate.new(vault_dir: @vault).accept(["platform-sync-c003"])

    result = Kit::Remember::TrustGate.new(vault_dir: @vault).pending

    assert_equal "kit_remember_pending", result["kind"]
    assert_equal ["platform-sync-c001"], result["items"].map { |item| item["id"] }
  end

  def test_cli_accept_json
    result = run_kit("remember", "accept", "--json", "platform-sync-c001")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "kit_remember_trust_update", payload["kind"]
    assert_equal "accepted", payload["status"]
    assert_equal ["platform-sync-c001"], payload["updated"].map { |item| item["id"] }
    assert_includes File.read(commitments_path), "- [ ] Follow up with Priya. _(accepted,"
  end

  def test_cli_missing_id_returns_failure
    result = run_kit("remember", "accept", "--json", "missing-id")

    assert_equal 1, result[:status]
    payload = JSON.parse(result[:stdout])
    assert_equal ["missing-id"], payload["missing_ids"]
  end

  private

  def write_commitments
    File.write(
      commitments_path,
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
        - [x] Send the rollout note. _(possible, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c002 -->

        <!-- kit:item platform-sync-c003 -->
        - [ ] Priya will update the API proposal. _(possible, owner: Priya, source: Platform Sync @ 00:03:00)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c003 -->
      MD
    )
  end

  def commitments_path
    File.join(@vault, "Commitments", "Commitments.md")
  end

  def run_kit(*args, env: {})
    stdout, stderr, status = Open3.capture3(env, RUBY, File.join(ROOT, "bin/kit"), *args, "--vault", @vault, chdir: ROOT)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
