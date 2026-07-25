# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require "time"

require_relative "../../../lib/kit"

class Kit::ReflectReportTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-reflect-report-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Weekly Briefs"))
    File.write(File.join(@vault, "Weekly Briefs", "Brief - 2026-07-18.md"), "# Weekly Brief\n")
    File.write(File.join(@vault, "Weekly Briefs", "Brief - 2026-07-25.md"), "# Weekly Brief\n")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_builds_reflection_without_promoting_possibles
    report = Kit::Reflect::Report.new(
      vault_dir: @vault,
      items: [
        item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed"),
        item("mine-open", "commitments_i_made", "accepted", "Cameron"),
        item("mine-dated", "commitments_i_made", "accepted", "Cameron", due_date: "2026-08-01"),
        item("other-open", "commitments_others_made", "trusted", "Priya"),
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

    assert_equal "kit_reflect", report["kind"]
    assert_equal "2026-07-25T12:00:00Z", report["generated_at"]
    assert_equal File.join(@vault, "Reflections", "Reflection - 2026-07-25.md"), report["artifact_path"]
    assert_equal "weekly", report.dig("filters", "period")
    assert_equal 4, report.dig("counts", "trusted_open_commitments")
    assert_equal 1, report.dig("counts", "trusted_completed_commitments")
    assert_equal 0.2, report.dig("counts", "trusted_completion_ratio")
    assert_equal 2, report.dig("counts", "waiting_on_me")
    assert_equal 1, report.dig("counts", "waiting_on_others")
    assert_equal 1, report.dig("counts", "open_decisions")
    assert_equal 1, report.dig("counts", "open_loops")
    assert_equal 1, report.dig("counts", "needs_review")
    assert_equal 3, report.dig("counts", "no_due_date_commitments")
    assert_equal ["mine-open", "other-open", "unclassified"], ids(report.dig("sections", "what_keeps_slipping"))
    assert_equal ["mine-open", "mine-dated"], ids(report.dig("sections", "commitment_load", "waiting_on_me"))
    assert_equal ["other-open"], ids(report.dig("sections", "commitment_load", "waiting_on_others"))
    assert_equal ["unclassified"], ids(report.dig("sections", "commitment_load", "unclassified"))
    assert_equal ["decision"], ids(report.dig("sections", "decision_bottlenecks"))
    assert_equal ["loop"], ids(report.dig("sections", "open_loop_pressure"))
    assert_equal ["review"], ids(report.dig("sections", "needs_review_backlog"))
    refute_includes ids(report["items"]), "rejected"
    assert_equal 2, report.dig("brief_history", "count")
    assert_equal "2026-07-18", report.dig("brief_history", "first_date")
    assert_equal "2026-07-25", report.dig("brief_history", "latest_date")
    assert_includes report.dig("sections", "insufficient_signal").join("\n"), "Recurring failure patterns"
  end

  def test_write_creates_markdown_artifact
    payload = Kit::Reflect::Report.new(
      vault_dir: @vault,
      items: [item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed")],
      warnings: ["Missing note: Decisions/Decisions.md"],
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    ).write

    content = File.read(payload["artifact_path"])

    assert_includes content, "# Weekly Reflection: 2026-07-25"
    assert_includes content, "## Follow-through snapshot"
    assert_includes content, "Current checkbox snapshot"
    assert_includes content, "## Brief history"
    assert_includes content, "Weekly briefs found: 2"
    assert_includes content, "## Warnings"
  end

  def test_missing_me_warns_and_disables_waiting_on_me
    report = Kit::Reflect::Report.new(
      vault_dir: @vault,
      items: [item("mine", "commitments_i_made", "accepted", "Cameron")],
      warnings: []
    ).to_h

    assert_empty report.dig("sections", "commitment_load", "waiting_on_me")
    assert_equal ["mine"], ids(report.dig("sections", "commitment_load", "unclassified"))
    assert_includes report["warnings"], "Missing --me or KIT_ME; waiting-on-me classification is disabled."
  end

  private

  def ids(items)
    Array(items).map { |item| item["id"] }
  end

  def item(id, bucket, status, owner, completion: "open", type: "commitment", due_date: nil)
    {
      "id" => id,
      "text" => "Item #{id}",
      "type" => type,
      "bucket" => bucket,
      "owner" => owner,
      "status" => status,
      "completion" => completion,
      "due_date" => due_date,
      "source" => "Platform Sync @ 00:00:12",
      "notice" => "/tmp/extracts/json/platform-sync.notice.json",
      "transcript" => "/tmp/transcripts/json/platform-sync.json",
      "speaker" => owner,
      "quote" => "Quote",
      "note_path" => File.join(@vault, "Commitments", "Commitments.md")
    }
  end
end
