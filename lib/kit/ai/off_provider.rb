# frozen_string_literal: true

module Kit::AI
  class OffProvider < Provider
    def name
      "off"
    end

    def enrich_notice(transcript:, deterministic_items:, retrieval_hits:)
      {
        "provider" => name,
        "notice_items" => [],
        "warnings" => ["AI enrichment is off."]
      }
    end

    def prepare_talking_points(person:, items:, retrieval_hits:)
      {
        "provider" => name,
        "talking_points" => [],
        "warnings" => ["AI enrichment is off."]
      }
    end

    def brief_draft_bullets(items:, retrieval_hits:)
      {
        "provider" => name,
        "bullets" => [],
        "warnings" => ["AI enrichment is off."]
      }
    end
  end
end
