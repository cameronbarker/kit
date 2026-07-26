# frozen_string_literal: true

module Kit::AI
  class MockProvider < Provider
    def name
      "mock"
    end

    def enrich_notice(transcript:, deterministic_items:, retrieval_hits:)
      source_item = Array(deterministic_items).first
      return empty_notice unless source_item

      {
        "provider" => name,
        "notice_items" => [
          {
            "type" => source_item["type"],
            "bucket" => source_item["bucket"],
            "text" => "AI draft: #{source_item['text']}",
            "owner" => source_item["owner"],
            "status" => "possible",
            "signals" => ["mock_ai"],
            "citation" => source_item["citation"],
            "retrieval_refs" => retrieval_refs(retrieval_hits)
          }
        ],
        "warnings" => []
      }
    end

    def prepare_talking_points(person:, items:, retrieval_hits:)
      seed = Array(items).first
      text = seed ? "Draft: discuss #{seed['text']}" : "Draft: ask #{person} what needs attention."
      {
        "provider" => name,
        "talking_points" => [
          draft_text(text, retrieval_hits)
        ],
        "warnings" => []
      }
    end

    def brief_draft_bullets(items:, retrieval_hits:)
      count = Array(items).length
      {
        "provider" => name,
        "bullets" => [
          draft_text("Draft: summarize #{count} Kit-managed item#{count == 1 ? '' : 's'}.", retrieval_hits)
        ],
        "warnings" => []
      }
    end

    private

    def empty_notice
      {
        "provider" => name,
        "notice_items" => [],
        "warnings" => []
      }
    end

    def draft_text(text, retrieval_hits)
      {
        "text" => text,
        "status" => "draft",
        "retrieval_refs" => retrieval_refs(retrieval_hits)
      }
    end

    def retrieval_refs(retrieval_hits)
      Array(retrieval_hits).first(3).map do |hit|
        {
          "path" => hit["path"],
          "docid" => hit["docid"],
          "collection" => hit["collection"],
          "score" => hit["score"]
        }
      end
    end
  end
end
