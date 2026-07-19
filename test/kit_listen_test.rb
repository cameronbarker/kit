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
    assert_includes stdout, "Planned lifecycle commands:"
    assert_includes stdout, "start [options] TITLE"
    assert_includes stdout, "pause [options]"
    assert_includes stdout, "resume [options]"
    assert_includes stdout, "rename-speaker"
    assert_includes stdout, "Target workflow:"
    assert_includes stdout, 'kit listen start "Platform Sync" --transcribe-on-stop'
  end

  def test_planned_lifecycle_command_is_intentional_stub
    stdout, stderr, status = Open3.capture3(File.join(ROOT, "bin/kit"), "listen", "pause")

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "kit listen pause is planned but not implemented yet."
    assert_includes stderr, "Pause the active recording"
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
end

Dir[File.expand_path("kit/listen/**/*_test.rb", __dir__)].sort.each do |path|
  require path
end
