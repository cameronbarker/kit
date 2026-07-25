# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::SurfaceParserTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-surface-parser-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Commitments"))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_parses_managed_items_and_checkbox_completion
    File.write(
      File.join(@vault, "Commitments", "Commitments.md"),
      <<~MD
        # Commitments

        Manual note outside managed blocks.

        <!-- kit:item platform-sync-c001 -->
        - [ ] Follow up with Priya. _(possible, owner: Cameron, source: Platform, Sync @ 00:00:12)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Due: 2026-08-01
          - Notice: /tmp/extracts/json/platform-sync.notice.json
          - Transcript: /tmp/transcripts/json/platform-sync.json
          - Speaker: Cameron / SPEAKER_00
          - Quote: "I'll follow up with Priya."
        <!-- /kit:item platform-sync-c001 -->

        <!-- kit:item platform-sync-c002 -->
        - [x] Send the rollout note. _(accepted, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c002 -->
      MD
    )

    result = Kit::Surface::Parser.new(vault_dir: @vault).parse

    item = result["items"].find { |candidate| candidate["id"] == "platform-sync-c001" }
    completed = result["items"].find { |candidate| candidate["id"] == "platform-sync-c002" }

    assert_equal "Follow up with Priya.", item["text"]
    assert_equal "possible", item["status"]
    assert_equal "Cameron", item["owner"]
    assert_equal "Platform, Sync @ 00:00:12", item["source"]
    assert_equal "commitments_i_made", item["bucket"]
    assert_equal "open", item["completion"]
    assert_equal "2026-08-01", item["due_date"]
    assert_equal "I'll follow up with Priya.", item["quote"]
    assert_equal "completed", completed["completion"]
    assert_includes result["warnings"], "Missing note: Open Loops/Open Loops.md"
    assert_includes result["warnings"], "Missing note: Decisions/Decisions.md"
  end
end
