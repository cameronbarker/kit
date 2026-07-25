# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require "time"

require_relative "../../../lib/kit"

class Kit::PreparePackTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-prepare-pack-test-")
    @vault = File.join(@tmpdir, "vault")
    FileUtils.mkdir_p(File.join(@vault, "Commitments"))
    FileUtils.mkdir_p(File.join(@vault, "Open Loops"))
    FileUtils.mkdir_p(File.join(@vault, "Decisions"))
    write_notes
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_builds_person_pack_with_trust_separation_and_artifact
    pack = Kit::Prepare::Pack.new(
      vault_dir: @vault,
      person: "Priya",
      me: "Cameron",
      now: Time.utc(2026, 7, 25, 12, 0, 0)
    )

    payload = pack.write

    assert_equal 1, payload["schema_version"]
    assert_equal "kit_prepare", payload["kind"]
    assert_equal "2026-07-25T12:00:00Z", payload["generated_at"]
    assert_equal @vault, payload["vault"]
    assert_equal "Priya", payload.dig("filters", "person")
    assert_equal "Cameron", payload.dig("filters", "me")
    assert_equal File.join(@vault, "1-1s", "Priya Prep.md"), payload["artifact_path"]

    assert_equal ["platform-sync-c001"], payload.dig("sections", "commitments").map { |item| item["id"] }
    assert_equal ["platform-sync-o001"], payload.dig("sections", "open_loops").map { |item| item["id"] }
    assert_equal ["platform-sync-d001"], payload.dig("sections", "recent_decisions").map { |item| item["id"] }
    assert_equal ["platform-sync-c002"], payload.dig("sections", "needs_review").map { |item| item["id"] }
    refute_includes payload["items"].map { |item| item["id"] }, "platform-sync-c003"
    refute_includes payload["items"].map { |item| item["id"] }, "platform-sync-c004"

    note = File.read(payload["artifact_path"])
    assert_includes note, "# Prep: Priya"
    assert_includes note, "## Open Commitments"
    assert_includes note, "Priya will update the API proposal. (`platform-sync-c001`)"
    assert_includes note, "## Needs Review"
    assert_includes note, "[needs review] Follow up with Priya. (`platform-sync-c002`)"
    assert_includes note, "Quote: Priya asked for the latest rollout risk."
  end

  def test_empty_pack_writes_none_found_sections
    payload = Kit::Prepare::Pack.new(vault_dir: @vault, person: "Morgan").write

    assert_equal 0, payload.dig("counts", "total")
    assert_empty payload["items"]
    assert File.file?(payload["artifact_path"])
    assert_includes File.read(payload["artifact_path"]), "- None found."
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
          - Transcript: /tmp/transcripts/json/platform-sync.json
          - Speaker: Priya / SPEAKER_01
          - Quote: "Priya asked for the latest rollout risk."
        <!-- /kit:item platform-sync-c001 -->

        <!-- kit:item platform-sync-c002 -->
        - [ ] Follow up with Priya. _(possible, owner: Cameron, source: Platform Sync @ 00:00:12)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
          - Speaker: Cameron / SPEAKER_00
          - Quote: "I'll follow up with Priya."
        <!-- /kit:item platform-sync-c002 -->

        <!-- kit:item platform-sync-c003 -->
        - [x] Send Priya the rollout note. _(accepted, owner: Cameron, source: Platform Sync @ 00:02:00)_
          - Type: commitment
          - Bucket: commitments_i_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c003 -->

        <!-- kit:item platform-sync-c004 -->
        - [ ] Priya will close the old thread. _(rejected, owner: Priya, source: Platform Sync @ 00:03:00)_
          - Type: commitment
          - Bucket: commitments_others_made
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-c004 -->
      MD
    )

    File.write(
      File.join(@vault, "Open Loops", "Open Loops.md"),
      <<~MD
        # Open Loops

        <!-- kit:item platform-sync-o001 -->
        - [ ] Should Priya join launch review? _(accepted, owner: Priya, source: Platform Sync @ 00:04:00)_
          - Type: open_loop
          - Bucket: open_loops
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-o001 -->
      MD
    )

    File.write(
      File.join(@vault, "Decisions", "Decisions.md"),
      <<~MD
        # Decisions

        <!-- kit:item platform-sync-d001 -->
        - [ ] Priya owns the beta API review. _(trusted, owner: Priya, source: Platform Sync @ 00:05:00)_
          - Type: decision
          - Bucket: decisions
          - Notice: /tmp/extracts/json/platform-sync.notice.json
        <!-- /kit:item platform-sync-d001 -->
      MD
    )
  end
end
