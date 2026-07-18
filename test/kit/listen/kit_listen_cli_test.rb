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
      phase recorder_pid title source_device recording_path
      metadata_path started_at ended_at latest_error
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
end
