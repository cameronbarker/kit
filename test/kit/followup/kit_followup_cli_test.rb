# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::FollowupCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-followup-cli-test-")
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
    result = run_kit("followup", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit followup [options]"
    assert_includes result[:stdout], "--overdue"
    assert_empty result[:stderr]
  end

  def test_followup_json_reads_temp_vault
    result = run_kit("followup", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:stderr]

    payload = JSON.parse(result[:stdout])
    assert_equal "kit_followup", payload["kind"]
    assert_equal @vault, payload["vault"]
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_equal ["mine-open"], payload.dig("sections", "waiting_on_me").map { |item| item["id"] }
    assert_equal ["other-open", "other-dated"], payload.dig("sections", "waiting_on_others").map { |item| item["id"] }
    assert_equal ["mine-open", "other-open"], payload.dig("sections", "needs_renegotiation").map { |item| item["id"] }
    assert_equal ["mine-possible"], payload.dig("sections", "needs_review").map { |item| item["id"] }
    assert_equal "2026-08-01", payload.dig("sections", "waiting_on_others", 1, "due_date")
  end

  def test_overdue_json_means_trusted_no_due_date_candidates
    result = run_kit("followup", "--overdue", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])

    assert_equal true, payload.dig("filters", "overdue")
    assert_equal ["mine-open", "other-open"], payload["items"].map { |item| item["id"] }
    assert_empty payload.dig("sections", "needs_review")
    assert_equal ["no_due_date"], payload["items"].map { |item| item["followup_reason"] }.uniq
  end

  def test_waiting_on_me_filter
    result = run_kit("followup", "--waiting-on-me", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])

    assert_equal ["mine-open", "mine-possible"], payload["items"].map { |item| item["id"] }
    assert_equal ["mine-open"], payload.dig("sections", "waiting_on_me").map { |item| item["id"] }
    assert_equal ["mine-possible"], payload.dig("sections", "needs_review").map { |item| item["id"] }
  end

  def test_human_output_warns_without_me
    result = run_kit("followup")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "Kit followup"
    assert_includes result[:stdout], "Waiting on others:"
    assert_includes result[:stdout], "Priya will update the API proposal."
    assert_includes result[:stderr], "Warning: Missing --me or KIT_ME"
  end

  def test_followup_uses_kit_vault_when_flag_absent
    result = run_kit_without_vault("followup", "--json", "--me", "Cameron", env: { "KIT_VAULT" => @vault })

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal @vault, payload["vault"]
  end

  private

  def write_notes
    File.write(
      File.join(@vault, "Commitments", "Commitments.md"),
      <<~MD
        # Commitments

        <!-- kit:item mine-open -->
        - [ ] Follow up with Priya. _(accepted, owner: Cameron, source: Platform Sync @ 00:00:12)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item mine-open -->

        <!-- kit:item mine-possible -->
        - [ ] Confirm whether I owe Rachel feedback. _(possible, owner: Cameron, source: Platform Sync @ 00:00:22)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item mine-possible -->

        <!-- kit:item other-open -->
        - [ ] Priya will update the API proposal. _(accepted, owner: Priya, source: Platform Sync @ 00:01:01)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item other-open -->

        <!-- kit:item other-dated -->
        - [ ] Morgan will send the launch checklist. _(accepted, owner: Morgan, source: Platform Sync @ 00:01:30)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Due: 2026-08-01
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item other-dated -->

        <!-- kit:item mine-done -->
        - [x] Send the rollout note. _(accepted, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item mine-done -->

        <!-- kit:item mine-rejected -->
        - [ ] Follow up on duplicate request. _(rejected, owner: Cameron, source: Platform Sync @ 00:02:30)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item mine-rejected -->
      MD
    )

    File.write(File.join(@vault, "Open Loops", "Open Loops.md"), "# Open Loops\n")
    File.write(File.join(@vault, "Decisions", "Decisions.md"), "# Decisions\n")
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
