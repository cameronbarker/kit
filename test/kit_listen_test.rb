# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

require_relative "../lib/kit"

class KitListenTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @tmpdir = Dir.mktmpdir("kit-listen-test-")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_entrypoint_loads_public_surface
    assert_equal Kit::VERSION, Kit::Listen::VERSION
    assert_operator Kit::Listen::Error, :<, Kit::Error
    assert_kind_of Module, Kit::Listen::Util
    assert_kind_of Module, Kit::Listen::Ffmpeg
    assert_kind_of Class, Kit::Listen::CLI
    assert_kind_of Class, Kit::Listen::Recorder
    assert_kind_of Class, Kit::Listen::RecordingState
    assert_kind_of Class, Kit::Listen::ChunkedSession
    assert_kind_of Class, Kit::Listen::Pipeline
    assert_equal ROOT, Kit::Listen::ROOT
    assert_equal File.join(ROOT, "lib", "kit", "listen", "python", "transcribe.py"), Kit::Listen::PYTHON_WORKER
  end

  def test_kit_listen_version
    stdout, stderr, status = Open3.capture3(File.join(ROOT, "bin/kit"), "listen", "version")

    assert status.success?, stderr
    assert_equal "kit listen #{Kit::Listen::VERSION}\n", stdout
  end

  def test_kit_listen_help_includes_planned_command_surface
    stdout, stderr, status = Open3.capture3(File.join(ROOT, "bin/kit"), "listen", "help")

    assert status.success?, stderr
    assert_includes stdout, "Implemented commands:"
    refute_includes stdout, "Planned transcript commands:"
    assert_includes stdout, "start [options] [DEVICE] TITLE"
    assert_includes stdout, "pause [options]"
    assert_includes stdout, "resume [options]"
    assert_includes stdout, "speakers [options] INPUT"
    assert_includes stdout, "rename-speaker"
    assert_includes stdout, "Target workflow:"
    assert_includes stdout, 'kit listen start Base "Platform Sync"'
  end

  def test_pause_without_active_session_reports_error
    stdout, stderr, status = Open3.capture3(
      File.join(ROOT, "bin/kit"),
      "listen",
      "pause",
      "--recordings-dir",
      File.join(@tmpdir, "recordings")
    )

    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "no active chunked listen session"
  end

  def test_kit_listen_status_uses_migrated_cli
    stdout, stderr, status = Open3.capture3(
      File.join(ROOT, "bin/kit"),
      "listen",
      "status",
      "--json",
      "--recordings-dir",
      File.join(@tmpdir, "recordings")
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal "idle", payload["phase"]
    assert_nil payload["recorder_pid"]
  end

  def test_real_worker_requires_flat_packaged_model_files
    input = File.join(@tmpdir, "meeting.m4a")
    output = File.join(@tmpdir, "raw.json")
    model_dir = File.join(@tmpdir, "model")
    FileUtils.mkdir_p(model_dir)
    File.write(input, "fake-audio")

    stdout, stderr, status = Open3.capture3(
      { "KIT_LISTEN_MODEL_DIR" => model_dir },
      "python3",
      Kit::Listen::PYTHON_WORKER,
      "--input",
      input,
      "--output",
      output
    )

    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "Packaged Listen model files are missing"
    assert_includes stderr, File.join(model_dir, "config.json")
    assert_includes stderr, File.join(model_dir, "model.bin")
    assert_includes stderr, File.join(model_dir, "wav2vec2_fairseq_base_ls960_asr_ls960.pth")
    assert_includes stderr, File.join(model_dir, "speaker-diarization.yml")
  end
end

Dir[File.expand_path("kit/listen/**/*_test.rb", __dir__)].sort.each do |path|
  require path
end
