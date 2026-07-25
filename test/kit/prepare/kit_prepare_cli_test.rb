# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::PrepareCLITest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  RUBY = RbConfig.ruby

  def setup
    @tmpdir = Dir.mktmpdir("kit-prepare-cli-test-")
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
    result = run_kit("prepare", "--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: kit prepare [options] [PERSON]"
    assert_includes result[:stdout], "--person NAME"
    assert_empty result[:stderr]
  end

  def test_prepare_json_writes_artifact_for_person_flag
    result = run_kit("prepare", "--person", "Priya", "--json", "--me", "Cameron")

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:stderr]

    payload = JSON.parse(result[:stdout])
    assert_equal "kit_prepare", payload["kind"]
    assert_equal @vault, payload["vault"]
    assert_equal "Priya", payload.dig("filters", "person")
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_equal 1, payload.dig("counts", "commitments")
    assert_equal 1, payload.dig("counts", "needs_review")
    assert File.file?(payload["artifact_path"])
    assert_includes File.read(payload["artifact_path"]), "# Prep: Priya"
  end

  def test_prepare_accepts_positional_person
    result = run_kit("prepare", "priya")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:stdout], "Kit prepare: priya"
    assert_includes result[:stdout], "Priya will update the API proposal."
    assert File.file?(File.join(@vault, "1-1s", "priya Prep.md"))
  end

  def test_prepare_uses_kit_vault_when_flag_absent
    result = run_kit_without_vault("prepare", "--json", "Priya", env: { "KIT_VAULT" => @vault })

    assert_equal 0, result[:status], result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal @vault, payload["vault"]
  end

  def test_prepare_rejects_missing_person
    result = run_kit("prepare")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Error: missing person"
  end

  def test_prepare_rejects_disagreeing_person_inputs
    result = run_kit("prepare", "--person", "Priya", "Morgan")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Error: --person and PERSON disagree"
  end

  def test_next_stub_is_unimplemented
    result = run_kit("prepare", "--next", "--json")

    assert_equal 2, result[:status]
    assert_empty result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "kit_prepare_unimplemented", payload["kind"]
    assert_equal false, payload["implemented"]
    assert_includes payload["message"], "planned but not implemented"
  end

  private

  def write_notes
    File.write(
      File.join(@vault, "Commitments", "Commitments.md"),
      <<~MD
        # Commitments

        <!-- kit:item platform-sync-c001 -->
        - [ ] Priya will update the API proposal. _(accepted, owner: Priya, source: Platform Sync @ 00:01:01)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c001 -->

        <!-- kit:item platform-sync-c002 -->
        - [ ] Follow up with Priya. _(possible, owner: Cameron, source: Platform Sync @ 00:00:12)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c002 -->
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
