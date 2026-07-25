# frozen_string_literal: true

require "minitest/autorun"
require "time"

require_relative "../../../lib/kit"

class Kit::FollowupReportTest < Minitest::Test
  def test_splits_trusted_commitments_and_keeps_possibles_separate
    report = Kit::Followup::Report.new(
      vault_dir: "/tmp/vault",
      items: [
        item("mine", "commitments_i_made", "accepted", "Cameron"),
        item("other", "commitments_others_made", "trusted", "Priya"),
        item("review", "commitments_i_made", "possible", "Cameron"),
        item("unknown", "commitments_unknown", "possible", "unknown"),
        item("rejected", "commitments_i_made", "rejected", "Cameron"),
        item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed")
      ],
      warnings: [],
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    ).to_h

    assert_equal "kit_followup", report["kind"]
    assert_equal "2026-07-25T12:00:00Z", report["generated_at"]
    assert_equal ["mine"], report.dig("sections", "waiting_on_me").map { |item| item["id"] }
    assert_equal ["other"], report.dig("sections", "waiting_on_others").map { |item| item["id"] }
    assert_equal ["mine", "other"], report.dig("sections", "needs_renegotiation").map { |item| item["id"] }
    assert_equal ["review", "unknown"], report.dig("sections", "needs_review").map { |item| item["id"] }
    assert_equal "no_due_date", report.dig("sections", "waiting_on_me", 0, "followup_reason")
    assert_equal "Quick update on: Item mine", report.dig("sections", "waiting_on_me", 0, "nudge")
    assert_equal 4, report.dig("counts", "total")
  end

  def test_overdue_filters_to_trusted_no_due_date_commitments
    report = Kit::Followup::Report.new(
      vault_dir: "/tmp/vault",
      items: [
        item("no-due", "commitments_i_made", "accepted", "Cameron"),
        item("has-due", "commitments_i_made", "accepted", "Cameron", due_date: "2026-08-01"),
        item("review", "commitments_i_made", "possible", "Cameron")
      ],
      warnings: [],
      me: "Cameron",
      overdue: true
    ).to_h

    assert_equal ["no-due"], report["items"].map { |item| item["id"] }
    assert_equal ["no-due"], report.dig("sections", "needs_renegotiation").map { |item| item["id"] }
    assert_empty report.dig("sections", "needs_review")
  end

  def test_missing_me_warns_and_disables_waiting_on_me
    report = Kit::Followup::Report.new(
      vault_dir: "/tmp/vault",
      items: [item("mine", "commitments_i_made", "accepted", "Cameron")],
      warnings: []
    ).to_h

    assert_empty report.dig("sections", "waiting_on_me")
    assert_includes report["warnings"], "Missing --me or KIT_ME; waiting-on-me classification is disabled."
  end

  private

  def item(id, bucket, status, owner, completion: "open", due_date: nil)
    {
      "id" => id,
      "text" => "Item #{id}",
      "type" => "commitment",
      "bucket" => bucket,
      "owner" => owner,
      "status" => status,
      "completion" => completion,
      "due_date" => due_date,
      "source" => "Platform Sync @ 00:00:12",
      "notice" => "/tmp/extract.notice.json",
      "transcript" => "/tmp/transcript.json",
      "speaker" => owner,
      "quote" => "Quote",
      "note_path" => "/tmp/vault/Commitments/Commitments.md"
    }
  end
end
