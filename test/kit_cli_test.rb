# frozen_string_literal: true

require "open3"
require "rbconfig"
require "json"
require "minitest/autorun"

class KitCLITest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RUBY = RbConfig.ruby

  def test_default_prints_help
    result = run_kit

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "kit 0.1.0"
    assert_includes result[:stdout], "listen -> notice -> remember -> surface"
    assert_includes result[:stdout], "notify"
    assert_includes result[:stdout], "listen"
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

  def test_notify_requires_message
    result = run_kit("notify")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Error: missing MESSAGE"
  end

  def test_notify_can_dry_run_without_sending_notification
    result = run_kit("notify", "Review", "open", "commitments", env: { "KIT_NOTIFY_DRY_RUN" => "1" })

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "terminal-notifier -title Kit -message Review open commitments"
    assert_includes result[:stdout], "-appIcon"
    assert_includes result[:stdout], "assets/kit-icon.png"
    assert_empty result[:stderr]
  end

  def test_status_json_exposes_app_bridge_contract
    result = run_kit("status", "--json")

    assert_equal 0, result[:status]
    assert_empty result[:stderr]

    payload = JSON.parse(result[:stdout])
    assert_equal 1, payload["schema_version"]
    assert_equal "0.1.0", payload["kit_version"]
    assert_equal "cli_json", payload.dig("integration", "mode")
    assert_includes payload.dig("integration", "stable_entrypoints"), ["kit", "status", "--json"]
    assert_equal ["kit", "listen", "start"], payload.dig("commands", "listen", "command")
    assert_equal ["kit", "listen", "pause", "--json"], payload.dig("commands", "listen_pause", "command")
  end

  def test_status_rejects_unexpected_arguments
    result = run_kit("status", "--plain")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Error: usage: kit status [--json]"
  end

  def test_listen_is_implemented_subcommand
    result = run_kit("listen", "version")

    assert_equal 0, result[:status]
    assert_equal "kit listen 0.1.0\n", result[:stdout]
    assert_empty result[:stderr]
  end

  def test_unknown_command_fails
    result = run_kit("nope")

    assert_equal 1, result[:status]
    assert_empty result[:stdout]
    assert_includes result[:stderr], "Unknown command: nope"
    assert_includes result[:stderr], "listen"
  end

  private

  def run_kit(*args, env: {})
    stdout, stderr, status = Open3.capture3(env, RUBY, File.join(ROOT, "bin/kit"), *args, chdir: ROOT)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end
end
