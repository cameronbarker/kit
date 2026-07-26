# frozen_string_literal: true

module Kit::AI
  class Provider
    def name
      self.class.name.split("::").last.sub(/Provider\z/, "").downcase
    end

    def enrich_notice(transcript:, deterministic_items:, retrieval_hits:)
      raise NotImplementedError
    end

    def prepare_talking_points(person:, items:, retrieval_hits:)
      raise NotImplementedError
    end

    def brief_draft_bullets(items:, retrieval_hits:)
      raise NotImplementedError
    end
  end
end
