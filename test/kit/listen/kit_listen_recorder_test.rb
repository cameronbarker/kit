# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "yaml"
require_relative "../../../lib/kit"

class Kit::ListenRecorderTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("leadership-transcripts-test-")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def with_env(key, value)
    previous = ENV[key]
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if previous.nil?
      ENV.delete(key)
    else
      ENV[key] = previous
    end
  end

  def test_resolve_device_prefers_cli_over_env
    with_env("KIT_LISTEN_AUDIO_DEVICE", "Current Env Device") do
      with_env("LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE", "Legacy Env Device") do
        assert_equal "CLI Device", Kit::Listen::Recorder.resolve_device("CLI Device")
      end
    end
  end

  def test_resolve_device_uses_env_when_cli_missing
    with_env("KIT_LISTEN_AUDIO_DEVICE", "Env Device") do
      with_env("LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE", "Legacy Env Device") do
        assert_equal "Env Device", Kit::Listen::Recorder.resolve_device(nil)
      end
    end
  end

  def test_resolve_device_uses_legacy_env_when_current_env_missing
    with_env("KIT_LISTEN_AUDIO_DEVICE", nil) do
      with_env("LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE", "Env Device") do
        assert_equal "Env Device", Kit::Listen::Recorder.resolve_device(nil)
      end
    end
  end

  def test_resolve_device_raises_when_missing
    with_env("KIT_LISTEN_AUDIO_DEVICE", nil) do
      with_env("LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE", nil) do
        error = assert_raises(Kit::Listen::Error) do
          Kit::Listen::Recorder.resolve_device(nil)
        end
        assert_match(/No audio device configured/, error.message)
      end
    end
  end

  def test_recorder_paths_and_ffmpeg_args
    now = Time.new(2026, 7, 17, 23, 56, 0)
    recordings_dir = File.join(@tmpdir, "recordings")
    recorder = Kit::Listen::Recorder.new(
      title: "Platform Sync",
      device: "Loopback Audio",
      format: "m4a",
      recordings_dir: recordings_dir,
      dry_run: true,
      now: now
    )

    assert_equal "platform-sync", recorder.slug
    assert_equal "20260717-235600-platform-sync", recorder.basename
    assert_equal File.join(recordings_dir, "20260717-235600-platform-sync.m4a"), recorder.recording_path
    assert_equal File.join(recordings_dir, "20260717-235600-platform-sync.yml"), recorder.metadata_path
    assert_equal(
      [
        "ffmpeg", "-f", "avfoundation", "-i", ":Loopback Audio",
        "-c:a", "aac", "-b:a", "128k",
        recorder.recording_path
      ],
      recorder.ffmpeg_args
    )

    wav = Kit::Listen::Recorder.new(
      title: "Platform Sync",
      device: "Loopback Audio",
      format: "wav",
      recordings_dir: recordings_dir,
      dry_run: true,
      now: now
    )
    assert_equal(
      [
        "ffmpeg", "-f", "avfoundation", "-i", ":Loopback Audio",
        "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
        wav.recording_path
      ],
      wav.ffmpeg_args
    )
  end

  def test_dry_run_record_writes_audio_and_metadata
    recordings_dir = File.join(@tmpdir, "recordings")
    now = Time.new(2026, 7, 17, 23, 56, 0)
    status = Kit::Listen::Recorder.new(
      title: "Platform Sync",
      device: "Loopback Audio",
      format: "m4a",
      recordings_dir: recordings_dir,
      dry_run: true,
      now: now
    ).record

    assert_equal 0, status
    audio = File.join(recordings_dir, "20260717-235600-platform-sync.m4a")
    meta_path = File.join(recordings_dir, "20260717-235600-platform-sync.yml")
    assert File.file?(audio)
    assert File.size(audio).positive?
    assert File.file?(meta_path)

    meta = YAML.safe_load(File.read(meta_path))
    assert_equal "Platform Sync", meta["title"]
    assert_equal "Loopback Audio", meta["source_device"]
    assert_equal audio, meta["recording_file"]
    assert meta["started_at"]
    assert meta["ended_at"]
    assert meta.key?("duration_seconds")
    assert_equal "m4a", meta["format"]
    assert_equal false, meta["transcribed"]
  end
end
