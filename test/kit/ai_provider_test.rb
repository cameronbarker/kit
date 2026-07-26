# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../lib/kit"

class KitAIProviderTest < Minitest::Test
  def test_off_provider_is_runtime_default
    provider = Kit::AI.provider(nil)

    assert_equal "off", provider.name
  end

  def test_mock_notice_enrichment_is_deterministic
    provider = Kit::AI::MockProvider.new
    item = {
      "type" => "commitment",
      "bucket" => "commitments_i_made",
      "text" => "I'll follow up with Priya.",
      "owner" => "Cameron",
      "citation" => { "quote" => "I'll follow up with Priya." }
    }

    first = provider.enrich_notice(transcript: {}, deterministic_items: [item], retrieval_hits: [])
    second = provider.enrich_notice(transcript: {}, deterministic_items: [item], retrieval_hits: [])

    assert_equal first, second
    assert_equal "AI draft: I'll follow up with Priya.", first.dig("notice_items", 0, "text")
    assert_equal "possible", first.dig("notice_items", 0, "status")
  end
end
