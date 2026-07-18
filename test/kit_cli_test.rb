# frozen_string_literal: true

require "open3"
require "rbconfig"
require "minitest/autorun"

class KitCLITest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RUBY = RbConfig.ruby

  def test_default_prints_help
    result = run_kit

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "kit 0.1.0"
    assert_includes result[:stdout], "listen -> notice -> remember -> surface"
    assert_includes result[:stdout], "remember"
    assert_empty result[:stderr]
  end

  def test_help_flags_print_help
    ["help", "--help", "-h"].each do |arg|
      result = run_kit(arg)

      assert_equal 0, result[:status]
      assert_includes result[:stdout], "Commands:"
      assert_empty result[:stderr]
    end
  end

  def test_version_prints_version
    result = run_kit("version")

    assert_equal 0, result[:status]
    assert_equal "kit 0.1.0\n", result[:stdout]
    assert_empty result[:stderr]
  end

  def test_planned_command_is_intentional_stub
    result = run_kit("notice")

    assert_equal 2, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "kit notice is planned but not implemented yet."
    assert_includes result[:stderr], "Extract commitments, decisions, risks, and open loops"
  end

  def test_listen_is_not_passthrough_yet
    result = run_kit("listen")

    assert_equal 2, result[:status]
    assert_includes result[:stderr], "kit listen is planned but not implemented yet."
  end

  def test_unknown_command_fails
    result = run_kit("nope")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Unknown command: nope"
    assert_includes result[:stderr], "listen"
  end

  private

  def run_kit(*args)
    stdout, stderr, status = Open3.capture3(RUBY, File.join(ROOT, "bin/kit"), *args, chdir: ROOT)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
