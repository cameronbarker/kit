# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "time"

require_relative "../../../lib/kit"

class Kit::NoticeExtractorTest < Minitest::Test
  def payload
    {
      "title" => "Platform Sync",
      "source_file" => "/tmp/platform-sync.m4a",
      "segments" => [
        {
          "speaker" => "Cameron",
          "raw_speaker" => "SPEAKER_00",
          "start" => 12.3,
          "end" => 18.1,
          "text" => "I'll follow up with Priya."
        },
        {
          "speaker" => "Priya",
          "raw_speaker" => "SPEAKER_01",
          "start" => 61.0,
          "end" => 70.0,
          "text" => "I'll update the API proposal."
        },
        {
          "speaker" => "Cameron",
          "raw_speaker" => "SPEAKER_00",
          "start" => 120.0,
          "end" => 127.0,
          "text" => "We decided to keep the beta behind a feature flag."
        },
        {
          "speaker" => "Priya",
          "raw_speaker" => "SPEAKER_01",
          "start" => 180.0,
          "end" => 190.0,
          "text" => "Can someone own the migration comms?"
        }
      ]
    }
  end

  def extract(me: "Cameron")
    Kit::Notice::Extractor.new(
      payload: payload,
      transcript_path: "/tmp/transcripts/json/platform-sync.json",
      me: me,
      now: Time.utc(2026, 7, 24, 12, 0, 0)
    ).extract
  end

  def test_extracts_commitments_by_configured_identity
    result = extract

    mine = result["items"].find { |item| item["bucket"] == "commitments_i_made" }
    others = result["items"].find { |item| item["bucket"] == "commitments_others_made" }

    assert_equal "I'll follow up with Priya.", mine["text"]
    assert_equal "Cameron", mine["owner"]
    assert_equal "possible", mine["status"]
    assert_equal "00:00:12", mine.dig("citation", "timestamp")
    assert_equal "I'll update the API proposal.", others["text"]
    assert_equal "Priya", others["owner"]
  end

  def test_extracts_decisions_and_open_loops
    result = extract

    decision = result["items"].find { |item| item["bucket"] == "decisions" }
    loop = result["items"].find { |item| item["bucket"] == "open_loops" }

    assert_equal "We decided to keep the beta behind a feature flag.", decision["text"]
    assert_equal "Can someone own the migration comms?", loop["text"]
  end

  def test_missing_identity_preserves_unknown_perspective
    result = extract(me: nil)

    assert_equal "unknown", result.dig("identity", "perspective")
    assert_includes result["warnings"].join("\n"), "No --me or KIT_ME supplied"
    assert result["items"].any? { |item| item["bucket"] == "commitments_unknown" }
    refute result["items"].any? { |item| item["bucket"] == "commitments_i_made" }
  end

  def test_empty_transcript_is_valid
    result = Kit::Notice::Extractor.new(
      payload: { "title" => "Empty", "segments" => [] },
      transcript_path: "/tmp/transcripts/json/empty.json",
      now: Time.utc(2026, 7, 24, 12, 0, 0)
    ).extract

    assert_equal [], result["items"]
    assert_equal [], result["warnings"]
  end
end
