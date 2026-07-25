# frozen_string_literal: true

require "minitest/autorun"
require "time"

require_relative "../../../lib/kit"

class Kit::SurfaceReportTest < Minitest::Test
  def test_possible_items_need_review_and_trusted_items_are_actionable
    report = Kit::Surface::Report.new(
      vault_dir: "/tmp/vault",
      items: [
        item("mine-review", "commitments_i_made", "possible", "Cameron"),
        item("mine-action", "commitments_i_made", "accepted", "Cameron"),
        item("other-action", "commitments_others_made", "trusted", "Priya"),
        item("loop-action", "open_loops", "trusted", "Priya"),
        item("rejected", "commitments_i_made", "rejected", "Cameron"),
        item("done", "commitments_i_made", "accepted", "Cameron", completion: "completed")
      ],
      warnings: [],
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    ).to_h

    assert_equal "kit_surface", report["kind"]
    assert_equal "2026-07-25T12:00:00Z", report["generated_at"]
    assert_equal 4, report.dig("counts", "open")
    assert_equal 1, report.dig("counts", "completed")
    assert_equal 1, report.dig("counts", "needs_review")
    assert_equal true, report["items"].find { |item| item["id"] == "rejected" }["rejected"]
    assert_equal ["mine-review"], report.dig("sections", "needs_review").map { |item| item["id"] }
    assert_equal ["mine-action"], report.dig("sections", "i_made").map { |item| item["id"] }
    assert_equal ["other-action"], report.dig("sections", "waiting_on_others").map { |item| item["id"] }
    assert_equal ["loop-action"], report.dig("sections", "open_loops").map { |item| item["id"] }
  end

  def test_needs_review_only_filters_items_and_sections
    report = Kit::Surface::Report.new(
      vault_dir: "/tmp/vault",
      items: [
        item("review", "commitments_unknown", "possible", "unknown"),
        item("action", "commitments_i_made", "accepted", "Cameron")
      ],
      warnings: [],
      needs_review_only: true
    ).to_h

    assert_equal ["review"], report["items"].map { |item| item["id"] }
    assert_equal ["review"], report.dig("sections", "needs_review").map { |item| item["id"] }
    assert_empty report.dig("sections", "i_made")
  end

  private

  def item(id, bucket, status, owner, completion: "open")
    {
      "id" => id,
      "text" => "Item #{id}",
      "type" => bucket == "open_loops" ? "open_loop" : "commitment",
      "bucket" => bucket,
      "owner" => owner,
      "status" => status,
      "completion" => completion,
      "source" => "Platform Sync @ 00:00:12",
      "notice" => "/tmp/extract.notice.json",
      "transcript" => "/tmp/transcript.json",
      "speaker" => owner,
      "quote" => "Quote",
      "note_path" => "/tmp/vault/Commitments/Commitments.md"
    }
  end
end
