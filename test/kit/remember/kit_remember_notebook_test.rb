# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../../../lib/kit"

class Kit::RememberNotebookTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-remember-test-")
    @vault = File.join(@tmpdir, "vault")
    @extract_path = File.join(@tmpdir, "extracts", "json", "platform-sync.notice.json")
    FileUtils.mkdir_p(File.dirname(@extract_path))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_writes_expected_notes_and_preserves_citations
    result = apply_notebook

    commitments = File.join(@vault, "Commitments", "Commitments.md")
    decisions = File.join(@vault, "Decisions", "Decisions.md")
    loops = File.join(@vault, "Open Loops", "Open Loops.md")
    inbox = File.join(@vault, "Inbox", "Kit Inbox.md")

    assert_equal [commitments, decisions, inbox, loops].sort, result["files"]
    assert File.file?(commitments)
    assert File.file?(decisions)
    assert File.file?(loops)
    assert File.file?(inbox)

    commitments_text = File.read(commitments)
    assert_includes commitments_text, "<!-- kit:item platform-sync-c001 -->"
    assert_includes commitments_text, "- [ ] Follow up with Priya. _(possible, owner: Cameron, source: Platform Sync @ 00:00:12)_"
    assert_includes commitments_text, "Transcript: /tmp/transcripts/json/platform-sync.json"
    assert_includes commitments_text, 'Quote: "I\'ll follow up with Priya."'

    inbox_text = File.read(inbox)
    assert_includes inbox_text, "<!-- kit:extract platform-sync -->"
    assert_includes inbox_text, "- Items remembered: 3"
  end

  def test_rerun_replaces_managed_block_without_duplication
    apply_notebook
    updated = extract
    updated["items"][0]["text"] = "Follow up with Priya and Rachel."
    plan = Kit::Remember::Planner.new(extract: updated, extract_path: @extract_path, vault_dir: @vault).plan

    Kit::Remember::Notebook.new(plan: plan).apply

    commitments = File.read(File.join(@vault, "Commitments", "Commitments.md"))
    assert_equal 1, commitments.scan("<!-- kit:item platform-sync-c001 -->").length
    assert_includes commitments, "Follow up with Priya and Rachel."
    refute_includes commitments, "- [ ] Follow up with Priya. _(possible"
  end

  def test_preserves_existing_non_kit_content
    commitments = File.join(@vault, "Commitments", "Commitments.md")
    FileUtils.mkdir_p(File.dirname(commitments))
    File.write(commitments, "# Commitments\n\nManual note\n")

    apply_notebook

    content = File.read(commitments)
    assert_includes content, "Manual note"
    assert_includes content, "<!-- kit:item platform-sync-c001 -->"
  end

  def test_dry_run_does_not_write_files
    result = apply_notebook(dry_run: true)

    assert_equal true, result["dry_run"]
    refute File.exist?(File.join(@vault, "Commitments", "Commitments.md"))
  end

  private

  def apply_notebook(dry_run: false)
    plan = Kit::Remember::Planner.new(extract: extract, extract_path: @extract_path, vault_dir: @vault).plan
    Kit::Remember::Notebook.new(plan: plan, dry_run: dry_run).apply
  end

  def extract
    {
      "schema_version" => 1,
      "kind" => "kit_notice_extract",
      "title" => "Platform Sync",
      "slug" => "platform-sync",
      "review_required" => true,
      "warnings" => ["review this"],
      "input" => {
        "transcript_json" => "/tmp/transcripts/json/platform-sync.json",
        "source_file" => "/tmp/platform-sync.m4a"
      },
      "items" => [
        item("platform-sync-c001", "commitment", "commitments_i_made", "Follow up with Priya.", "Cameron"),
        item("platform-sync-d001", "decision", "decisions", "Keep the beta behind a feature flag.", nil),
        item("platform-sync-o001", "open_loop", "open_loops", "No owner for migration comms.", nil)
      ]
    }
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
        "start" => 12.3,
        "end" => 18.1,
        "timestamp" => "00:00:12",
        "quote" => "I'll follow up with Priya."
      }
    }
  end
end
