# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::ReflectCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-reflect-cli-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Commitments"))
    FileUtils.mkdir_p(File.join(@vault, "Open Loops"))
    FileUtils.mkdir_p(File.join(@vault, "Decisions"))
    FileUtils.mkdir_p(File.join(@vault, "Weekly Briefs"))
    File.write(File.join(@vault, "Weekly Briefs", "Brief - 2026-07-18.md"), "# Weekly Brief\n")
    write_notes
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_help_prints_usage
    result = run_kit("reflect", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit reflect [options]"
    assert_includes result[:stdout], "--me NAME"
    assert_empty result[:stderr]
  end

  def test_reflect_json_reads_temp_vault_and_writes_artifact
    result = run_kit("reflect", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:stderr]

    payload = JSON.parse(result[:stdout])
    assert_equal "kit_reflect", payload["kind"]
    assert_equal @vault, payload["vault"]
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_equal "weekly", payload.dig("filters", "period")
    assert_equal ["mine-open", "other-open"], ids(payload.dig("sections", "what_keeps_slipping"))
    assert_equal ["mine-open"], ids(payload.dig("sections", "commitment_load", "waiting_on_me"))
    assert_equal ["other-open"], ids(payload.dig("sections", "commitment_load", "waiting_on_others"))
    assert_equal ["decision-open"], ids(payload.dig("sections", "decision_bottlenecks"))
    assert_equal ["loop-open"], ids(payload.dig("sections", "open_loop_pressure"))
    assert_equal ["mine-possible", "loop-possible"], ids(payload.dig("sections", "needs_review_backlog"))
    assert_equal 1, payload.dig("brief_history", "count")
    assert File.file?(payload["artifact_path"])
    assert_includes File.read(payload["artifact_path"]), "# Weekly Reflection:"
    assert_includes File.read(payload["artifact_path"]), "Insufficient signal"
  end

  def test_human_output_includes_artifact_and_sections
    result = run_kit("reflect", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "Kit reflect"
    assert_includes result[:stdout], "note:"
    assert_includes result[:stdout], "Follow-through snapshot:"
    assert_includes result[:stdout], "What keeps slipping:"
    assert_includes result[:stdout], "Needs review backlog:"
    assert_includes result[:stdout], "Brief history:"
  end

  def test_reflect_uses_env_defaults_when_flags_absent
    result = run_kit_without_vault("reflect", "--json", env: { "KIT_VAULT" => @vault, "KIT_ME" => "Cameron" })

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal @vault, payload["vault"]
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_empty payload["warnings"]
  end

  def test_reflect_warns_without_me
    result = run_kit("reflect", "--json")

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_empty payload.dig("sections", "commitment_load", "waiting_on_me")
    assert_includes payload["warnings"], "Missing --me or KIT_ME; waiting-on-me classification is disabled."
  end

  def test_reflect_rejects_unexpected_arguments
    result = run_kit("reflect", "monthly")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Error: unexpected arguments: monthly"
  end

  private

  def ids(items)
    Array(items).map { |item| item["id"] }
  end

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

        <!-- kit:item mine-done -->
        - [x] Send the rollout note. _(accepted, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item mine-done -->

        <!-- kit:item rejected-open -->
        - [ ] Follow up on duplicate request. _(rejected, owner: Cameron, source: Platform Sync @ 00:02:30)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item rejected-open -->
      MD
    )

    File.write(
      File.join(@vault, "Open Loops", "Open Loops.md"),
      <<~MD
        # Open Loops

        <!-- kit:item loop-open -->
        - [ ] Confirm launch dependency. _(accepted, owner: Priya, source: Platform Sync @ 00:03:00)_
          - Type: open_loop
          - Bucket: open_loops
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item loop-open -->

        <!-- kit:item loop-possible -->
        - [ ] Maybe follow up on design staffing. _(possible, owner: unknown, source: Platform Sync @ 00:03:30)_
          - Type: open_loop
          - Bucket: open_loops
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item loop-possible -->
      MD
    )

    File.write(
      File.join(@vault, "Decisions", "Decisions.md"),
      <<~MD
        # Decisions

        <!-- kit:item decision-open -->
        - [ ] Decide whether to slip beta. _(accepted, owner: Cameron, source: Platform Sync @ 00:04:00)_
          - Type: decision
          - Bucket: decisions
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item decision-open -->
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
