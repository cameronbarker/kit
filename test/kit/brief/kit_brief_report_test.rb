# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require "time"

require_relative "../../../lib/kit"

class Kit::BriefReportTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-brief-report-test-")
    @vault = File.join(@tmpdir, "vault")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_builds_trusted_brief_sections_without_promoting_possibles
    report = Kit::Brief::Report.new(
      vault_dir: @vault,
      items: [
        item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed"),
        item("done-possible", "commitments_i_made", "possible", "Cameron", completion: "completed"),
        item("mine", "commitments_i_made", "accepted", "Cameron"),
        item("other", "commitments_others_made", "trusted", "Priya"),
        item("unclassified", "commitments_unknown", "accepted", "Morgan"),
        item("decision", "decisions", "accepted", "Cameron", type: "decision"),
        item("loop", "open_loops", "trusted", "Priya", type: "open_loop"),
        item("review", "commitments_i_made", "possible", "Cameron"),
        item("rejected", "commitments_i_made", "rejected", "Cameron")
      ],
      warnings: [],
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    ).to_h

    assert_equal "kit_brief", report["kind"]
    assert_equal "2026-07-25T12:00:00Z", report["generated_at"]
    assert_equal File.join(@vault, "Weekly Briefs", "Brief - 2026-07-25.md"), report["artifact_path"]
    assert_equal ["done"], ids(report.dig("sections", "what_moved"))
    assert_equal ["mine"], ids(report.dig("sections", "waiting_on_me"))
    assert_equal ["other"], ids(report.dig("sections", "waiting_on_others"))
    assert_equal ["unclassified"], ids(report.dig("sections", "open_commitments_unclassified"))
    assert_equal ["decision"], ids(report.dig("sections", "decisions_needed"))
    assert_equal ["loop"], ids(report.dig("sections", "open_loops"))
    assert_equal ["review"], ids(report.dig("sections", "needs_review"))
    assert_equal 3, report.dig("counts", "recommended_next_actions")
    refute_includes ids(report["items"]), "rejected"
    assert_includes report.dig("sections", "stakeholder_update_draft").join("\n"), "Draft:"
    assert_equal ["Insufficient history in v1."], report.dig("sections", "insufficient_history")
  end

  def test_write_creates_markdown_artifact
    payload = Kit::Brief::Report.new(
      vault_dir: @vault,
      items: [item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed")],
      warnings: ["Missing note: Decisions/Decisions.md"],
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    ).write

    content = File.read(payload["artifact_path"])

    assert_includes content, "# Weekly Brief: 2026-07-25"
    assert_includes content, "## What moved"
    assert_includes content, "Item done (`done`)"
    assert_includes content, "## What changed since last week"
    assert_includes content, "Insufficient history in v1."
    assert_includes content, "## Warnings"
  end

  def test_missing_me_warns_and_disables_waiting_on_me
    report = Kit::Brief::Report.new(
      vault_dir: @vault,
      items: [item("mine", "commitments_i_made", "accepted", "Cameron")],
      warnings: []
    ).to_h

    assert_empty report.dig("sections", "waiting_on_me")
    assert_equal ["mine"], ids(report.dig("sections", "open_commitments_unclassified"))
    assert_includes report["warnings"], "Missing --me or KIT_ME; waiting-on-me classification is disabled."
  end

  private

  def ids(items)
    Array(items).map { |item| item["id"] }
  end

  def item(id, bucket, status, owner, completion: "open", type: "commitment")
    {
      "id" => id,
      "text" => "Item #{id}",
      "type" => type,
      "bucket" => bucket,
      "owner" => owner,
      "status" => status,
      "completion" => completion,
      "due_date" => nil,
      "source" => "Platform Sync @ 00:00:12",
      "notice" => "/tmp/extract.notice.json",
      "transcript" => "/tmp/transcript.json",
      "speaker" => owner,
      "quote" => "Quote",
      "note_path" => File.join(@vault, "Commitments", "Commitments.md")
    }
  end
end
