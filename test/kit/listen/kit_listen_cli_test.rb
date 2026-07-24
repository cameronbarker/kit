# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../../lib/kit"

class Kit::ListenCLITest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("leadership-transcripts-test-")
    @input = File.join(@tmpdir, "platform_sync.m4a")
    File.write(@input, "fake-audio")
    @transcripts_dir = File.join(@tmpdir, "transcripts")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def capture_json_cli(*args)
    out = StringIO.new
    err = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = out
    $stderr = err
    status = Kit::Listen::CLI.run(args)
    [status, out.string, err.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def parse_json_stdout(stdout)
    JSON.parse(stdout)
  end

  def test_cli_mock_transcribe
    status = Kit::Listen::CLI.run(
      [
        "transcribe",
        "--mock",
        "--transcripts-dir",
        @transcripts_dir,
        @input
      ]
    )
    assert_equal 0, status
    assert File.file?(File.join(@transcripts_dir, "md", "platform-sync.md"))
  end

  def test_speakers_command_shows_map_and_samples
    assert_equal 0, Kit::Listen::CLI.run(
      [
        "transcribe",
        "--mock",
        "--transcripts-dir",
        @transcripts_dir,
        @input
      ]
    )

    status, stdout, stderr = capture_json_cli(
      "speakers",
      "--transcripts-dir", @transcripts_dir,
      @input
    )
    assert_equal 0, status, stderr
    assert_includes stdout, "Speaker map: #{File.join(@transcripts_dir, 'maps', 'platform-sync.speaker-map.yml')}"
    assert_includes stdout, "SPEAKER_00 -> SPEAKER_00"
    assert_includes stdout, "[00:01:12] I'll follow up with DevOps and confirm the migration window."
  end

  def test_speakers_command_emits_json
    assert_equal 0, Kit::Listen::CLI.run(
      [
        "transcribe",
        "--mock",
        "--transcripts-dir",
        @transcripts_dir,
        @input
      ]
    )

    status, stdout, stderr = capture_json_cli(
      "speakers",
      "--json",
      "--transcripts-dir", @transcripts_dir,
      @input
    )
    assert_equal 0, status, stderr
    payload = parse_json_stdout(stdout)
    assert_equal File.join(@transcripts_dir, "maps", "platform-sync.speaker-map.yml"), payload["speaker_map"]
    assert_equal "SPEAKER_00", payload["speakers"][0]["raw_speaker"]
    assert_equal "00:01:12", payload["speakers"][0]["samples"][0]["timestamp"]
  end

  def test_rename_speaker_command_updates_map_and_rerenders
    assert_equal 0, Kit::Listen::CLI.run(
      [
        "transcribe",
        "--mock",
        "--transcripts-dir",
        @transcripts_dir,
        @input
      ]
    )

    status, _stdout, stderr = capture_json_cli(
      "rename-speaker",
      "--transcripts-dir", @transcripts_dir,
      @input,
      "SPEAKER_00",
      "Cameron"
    )
    assert_equal 0, status, stderr

    map = YAML.safe_load(File.read(File.join(@transcripts_dir, "maps", "platform-sync.speaker-map.yml")))
    assert_equal "Cameron", map["SPEAKER_00"]

    markdown = File.read(File.join(@transcripts_dir, "md", "platform-sync.md"))
    assert_includes markdown, "[00:01:12] Cameron:"
  end

  def test_dry_run_record_with_transcribe_mock_updates_metadata
    recordings_dir = File.join(@tmpdir, "recordings")
    status = Kit::Listen::CLI.run(
      [
        "record",
        "--dry-run",
        "--device", "Loopback Audio",
        "--format", "m4a",
        "--transcribe",
        "--mock",
        "--recordings-dir", recordings_dir,
        "--transcripts-dir", @transcripts_dir,
        "Platform Sync"
      ]
    )
    assert_equal 0, status

    audio = Dir[File.join(recordings_dir, "*-platform-sync.m4a")].first
    meta_path = Dir[File.join(recordings_dir, "*-platform-sync.yml")].first
    refute_nil audio
    refute_nil meta_path

    meta = YAML.safe_load(File.read(meta_path))
    assert_equal true, meta["transcribed"]
    assert File.file?(meta["transcript_json"])
    assert File.file?(meta["transcript_md"])
    assert_equal File.join(@transcripts_dir, "json", "#{File.basename(audio, '.*')}.json"), meta["transcript_json"]
  end

  def test_stop_with_no_active_recording
    recordings_dir = File.join(@tmpdir, "recordings")
    status, stdout, = capture_json_cli(
      "stop", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    payload = parse_json_stdout(stdout)
    assert_equal true, payload["ok"]
    assert_equal "noop", payload["action"]
    assert_equal "no active recording", payload["message"]
    assert_equal "idle", payload["phase"]
    assert_nil payload["recorder_pid"]
  end

  def test_latest_json_zero_one_and_many_metadata_files
    recordings_dir = File.join(@tmpdir, "recordings")

    status, stdout, = capture_json_cli(
      "latest", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    empty = parse_json_stdout(stdout)
    assert_equal false, empty["found"]
    assert_nil empty["metadata_path"]
    assert_nil empty["recording"]

    FileUtils.mkdir_p(recordings_dir)
    one = File.join(recordings_dir, "20260717-100000-one.yml")
    File.write(one, YAML.dump("title" => "One", "transcribed" => false))

    status, stdout, = capture_json_cli(
      "latest", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    single = parse_json_stdout(stdout)
    assert_equal true, single["found"]
    assert_equal one, single["metadata_path"]
    assert_equal "One", single["recording"]["title"]
    assert_equal false, single["recording"]["transcribed"]

    two = File.join(recordings_dir, "20260717-110000-two.yml")
    File.write(two, YAML.dump("title" => "Two", "transcribed" => true))

    status, stdout, = capture_json_cli(
      "latest", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    many = parse_json_stdout(stdout)
    assert_equal true, many["found"]
    assert_equal two, many["metadata_path"]
    assert_equal "Two", many["recording"]["title"]
    assert_equal true, many["recording"]["transcribed"]
  end

  def test_json_contracts_for_status_latest_stop
    recordings_dir = File.join(@tmpdir, "recordings")
    status_keys = %w[
      mode
      phase recorder_pid title source_device recording_path
      metadata_path started_at ended_at latest_error
      session_id chunks_dir chunk_count transcript_json transcript_md
      progress_message
    ]
    latest_keys = %w[found metadata_path recording]
    stop_keys = %w[ok action message phase recorder_pid]

    status, stdout, = capture_json_cli("status", "--json", "--recordings-dir", recordings_dir)
    assert_equal 0, status
    assert_equal status_keys.sort, parse_json_stdout(stdout).keys.sort

    status, stdout, = capture_json_cli("latest", "--json", "--recordings-dir", recordings_dir)
    assert_equal 0, status
    assert_equal latest_keys.sort, parse_json_stdout(stdout).keys.sort

    status, stdout, = capture_json_cli("stop", "--json", "--recordings-dir", recordings_dir)
    assert_equal 0, status
    assert_equal stop_keys.sort, parse_json_stdout(stdout).keys.sort
  end

  def test_chunked_start_accepts_positional_device
    recordings_dir = File.join(@tmpdir, "recordings")

    status, stdout, stderr = capture_json_cli(
      "start",
      "Base",
      "--json",
      "--dry-run",
      "--recordings-dir", recordings_dir,
      "Meeting"
    )
    assert_equal 0, status, stderr
    started = parse_json_stdout(stdout)
    assert_equal "started", started["action"]
    assert_equal "recording", started["phase"]

    meta = YAML.safe_load(File.read(started["metadata_path"]))
    assert_equal "Base", meta["source_device"]
    assert_equal "Meeting", meta["title"]
  ensure
    Kit::Listen::CLI.run(["stop", "--json", "--mock", "--recordings-dir", recordings_dir])
  end

  def test_chunked_start_rejects_device_twice
    status, _stdout, stderr = capture_json_cli(
      "start",
      "Base",
      "--device", "Other",
      "--json",
      "--dry-run",
      "Meeting"
    )
    assert_equal 1, status
    assert_match(/device specified twice/, stderr)
  end

  def test_chunked_start_pause_resume_stop_dry_run_merges_transcript
    recordings_dir = File.join(@tmpdir, "recordings")
    transcripts_dir = File.join(@tmpdir, "transcripts")

    status, stdout, = capture_json_cli(
      "start",
      "--json",
      "--dry-run",
      "--mock",
      "--device", "Loopback Audio",
      "--chunk-seconds", "30",
      "--recordings-dir", recordings_dir,
      "--transcripts-dir", transcripts_dir,
      "Platform Sync"
    )
    assert_equal 0, status
    started = parse_json_stdout(stdout)
    assert_equal "started", started["action"]
    assert_equal "recording", started["phase"]
    assert_equal 1, started["chunk_count"]
    session_id = started["session_id"]

    status, stdout, = capture_json_cli("pause", "--json", "--recordings-dir", recordings_dir)
    assert_equal 0, status
    paused = parse_json_stdout(stdout)
    assert_equal "paused", paused["action"]
    assert_equal "paused", paused["phase"]
    assert_equal session_id, paused["session_id"]

    status, stdout, = capture_json_cli(
      "resume",
      "--json",
      "--dry-run",
      "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    resumed = parse_json_stdout(stdout)
    assert_equal "resumed", resumed["action"]
    assert_equal "recording", resumed["phase"]
    assert_equal 2, resumed["chunk_count"]

    status, stdout, = capture_json_cli(
      "stop",
      "--json",
      "--mock",
      "--recordings-dir", recordings_dir,
      "--transcripts-dir", transcripts_dir
    )
    assert_equal 0, status
    stopped = parse_json_stdout(stdout)
    assert_equal "completed", stopped["action"]
    assert_equal "completed", stopped["phase"]
    assert_equal 2, stopped["chunk_count"]
    assert File.file?(stopped["transcript_json"])
    assert File.file?(stopped["transcript_md"])

    final = JSON.parse(File.read(stopped["transcript_json"]))
    assert_equal "Platform Sync", final["title"]
    assert_equal 4, final["segments"].length
    assert_equal [1, 1, 2, 2], final["segments"].map { |segment| segment["chunk_index"] }
    assert_operator final["segments"][2]["start"], :>, final["segments"][1]["start"]

    latest_status, latest_stdout, = capture_json_cli(
      "latest", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, latest_status
    latest = parse_json_stdout(latest_stdout)
    assert_equal true, latest["found"]
    assert_equal stopped["metadata_path"], latest["metadata_path"]
    assert_equal true, latest["recording"]["transcribed"]
  end
end
