# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "time"

require_relative "../../lib/kit"

class KitAppBridgeStatusTest < Minitest::Test
  def test_status_payload_has_stable_menu_bar_contract
    status = Kit::AppBridge::Status.new(
      now: Time.utc(2026, 7, 18, 12, 0, 0),
      executable: "/repo/bin/kit",
      ruby: "/usr/bin/ruby",
      notification_executable: "definitely-not-installed-kit-test"
    ).to_h

    assert_equal 1, status["schema_version"]
    assert_equal "0.1.0", status["kit_version"]
    assert_equal "2026-07-18T12:00:00Z", status["generated_at"]
    assert_equal "setup", status.dig("health", "indicator")
    assert_equal "cli_json", status.dig("integration", "mode")
    assert_equal ["/usr/bin/ruby", "/repo/bin/kit"], status.dig("integration", "kit_command")
    assert_includes status.dig("integration", "stable_entrypoints"), ["kit", "status", "--json"]
    assert_includes status.dig("integration", "stable_entrypoints"), ["kit", "notice", "--json"]
    assert_includes status.dig("integration", "stable_entrypoints"), ["kit", "remember", "--json"]
    assert_equal ["kit", "surface", "--json"], status.dig("commands", "open_loops", "command")
    assert_equal true, status.dig("commands", "open_loops", "implemented")
    assert_equal true, status.dig("commands", "today_surface", "implemented")
    assert_equal true, status.dig("commands", "listen", "implemented")
    assert_equal true, status.dig("commands", "listen_pause", "implemented")
    assert_equal ["kit", "listen", "stop", "--json"], status.dig("commands", "listen_stop", "command")
    assert_equal Kit::Notifications::DEFAULT_APP_ICON, status.dig("notifications", "app_icon")
    assert_equal false, status.dig("notifications", "available")
  end

  def test_status_payload_is_json_serializable
    status = Kit::AppBridge::Status.new(now: Time.utc(2026, 7, 18)).to_h

    parsed = JSON.parse(JSON.generate(status))

    assert_equal status, parsed
  end
end
