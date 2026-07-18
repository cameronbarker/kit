# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "time"
require "yaml"
require_relative "../../../lib/kit"

class Kit::ListenRecordingStateTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("leadership-transcripts-test-")
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

  def test_idle_to_recording_to_completed_state_transition
    recordings_dir = File.join(@tmpdir, "recordings")
    state = Kit::Listen::RecordingState.new(recordings_dir)
    assert_equal "idle", state.read["phase"]

    status, stdout, = capture_json_cli(
      "status", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    idle = parse_json_stdout(stdout)
    assert_equal "idle", idle["phase"]
    assert_nil idle["recorder_pid"]

    now = Time.new(2026, 7, 17, 23, 56, 0)
    record_status = Kit::Listen::Recorder.new(
      title: "Platform Sync",
      device: "Loopback Audio",
      format: "m4a",
      recordings_dir: recordings_dir,
      dry_run: true,
      now: now
    ).record
    assert_equal 0, record_status

    final = state.read
    assert_equal "completed", final["phase"]
    assert_nil final["recorder_pid"]
    assert_equal "Platform Sync", final["title"]
    assert_equal "Loopback Audio", final["source_device"]
    assert final["recording_path"]
    assert final["metadata_path"]
    assert final["started_at"]
    assert final["ended_at"]
    assert_nil final["latest_error"]
  end

  def test_transcribed_false_to_true_keeps_completed_state
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

    meta_path = Dir[File.join(recordings_dir, "*-platform-sync.yml")].first
    meta = YAML.safe_load(File.read(meta_path))
    assert_equal true, meta["transcribed"]

    state = Kit::Listen::RecordingState.new(recordings_dir).read
    assert_equal "completed", state["phase"]
    assert_nil state["latest_error"]
  end

  def test_stale_pid_recovery_to_error_without_artifacts
    recordings_dir = File.join(@tmpdir, "recordings")
    state = Kit::Listen::RecordingState.new(recordings_dir)
    state.write!(
      "phase" => "recording",
      "recorder_pid" => 999_999_999,
      "title" => "Gone",
      "source_device" => "Loopback Audio",
      "recording_path" => File.join(recordings_dir, "missing.m4a"),
      "metadata_path" => File.join(recordings_dir, "missing.yml"),
      "started_at" => Time.now.iso8601,
      "ended_at" => nil,
      "latest_error" => nil
    )

    status, stdout, = capture_json_cli(
      "status", "--json", "--recordings-dir", recordings_dir
    )
    assert_equal 0, status
    payload = parse_json_stdout(stdout)
    assert_equal "error", payload["phase"]
    assert_nil payload["recorder_pid"]
    assert_match(/stale/i, payload["latest_error"])
  end

  def test_stale_pid_recovery_to_completed_with_artifacts
    recordings_dir = File.join(@tmpdir, "recordings")
    FileUtils.mkdir_p(recordings_dir)
    audio = File.join(recordings_dir, "20260717-120000-stale.m4a")
    meta = File.join(recordings_dir, "20260717-120000-stale.yml")
    File.write(audio, "audio")
    File.write(meta, YAML.dump("title" => "Stale", "transcribed" => false))

    state = Kit::Listen::RecordingState.new(recordings_dir)
    state.write!(
      "phase" => "recording",
      "recorder_pid" => 999_999_999,
      "title" => "Stale",
      "source_device" => "Loopback Audio",
      "recording_path" => audio,
      "metadata_path" => meta,
      "started_at" => Time.now.iso8601,
      "ended_at" => nil,
      "latest_error" => nil
    )

    recovered = state.recover_if_stale!
    assert_equal "completed", recovered["phase"]
    assert_nil recovered["recorder_pid"]
    assert_match(/stale/i, recovered["latest_error"])
  end
end
