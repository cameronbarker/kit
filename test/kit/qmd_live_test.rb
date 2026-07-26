# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../lib/kit"

class KitQmdLiveTest < Minitest::Test
  def test_live_qmd_status_when_enabled
    skip "set KIT_QMD_LIVE=1 to run live qmd smoke test" unless ENV["KIT_QMD_LIVE"] == "1"
    skip "qmd not found on PATH" unless Kit::Qmd::Client.new.available?

    result = Kit::Qmd::Client.new.status

    assert result.success?, result.stderr
  end
end
