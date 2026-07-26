# frozen_string_literal: true

module Kit::Notice
  class Enrichment
    DEFAULT_LIMIT = 5

    attr_reader :extract, :transcript, :provider, :retrieval, :retrieval_enabled, :retrieval_query

    def initialize(extract:, transcript:, provider:, retrieval: nil, retrieval_enabled: true, retrieval_query: nil)
      @extract = extract
      @transcript = transcript
      @provider = provider
      @retrieval = retrieval || Kit::Retrieval.new(limit: DEFAULT_LIMIT)
      @retrieval_enabled = retrieval_enabled
      @retrieval_query = clean(retrieval_query)
    end

    def apply
      deterministic_items = Array(extract["items"]).map do |item|
        add_provenance(item, "deterministic")
      end
      retrieval_payload = retrieve
      ai_payload = provider.enrich_notice(
        transcript: transcript,
        deterministic_items: deterministic_items,
        retrieval_hits: retrieval_payload.fetch("hits", [])
      )
      ai_items = assign_ai_ids(Array(ai_payload["notice_items"]))

      extract.merge(
        "items" => deterministic_items + ai_items,
        "enrichment" => {
          "enabled" => true,
          "provider" => provider.name,
          "retrieval" => retrieval_payload,
          "counts" => {
            "deterministic_items" => deterministic_items.length,
            "ai_items" => ai_items.length,
            "total_items" => deterministic_items.length + ai_items.length
          },
          "warnings" => Array(ai_payload["warnings"]) + Array(retrieval_payload["warnings"])
        }
      )
    end

    private

    def retrieve
      return disabled_retrieval unless retrieval_enabled

      retrieval.retrieve(retrieval_query || default_query)
    end

    def disabled_retrieval
      {
        "available" => false,
        "mode" => nil,
        "collection" => nil,
        "query" => nil,
        "hits" => [],
        "warnings" => ["Retrieval disabled for this turn."]
      }
    end

    def default_query
      title = transcript["title"].to_s.strip
      segments = Array(transcript["segments"]).map { |segment| segment["text"].to_s.strip }.reject(&:empty?)
      ([title] + segments.first(3)).reject(&:empty?).join(" ")
    end

    def add_provenance(item, value)
      with_provenance = item.merge("enrichment" => value)
      citation = with_provenance["citation"]
      return with_provenance unless citation

      with_provenance.merge("citations" => [citation])
    end

    def assign_ai_ids(items)
      counts = existing_counts
      items.map do |item|
        normalized = normalize_ai_item(item)
        prefix = prefix_for(normalized["type"])
        counts[prefix] += 1
        normalized.merge("id" => "#{extract.fetch('slug')}-#{prefix}#{format('%03d', counts[prefix])}")
      end
    end

    def normalize_ai_item(item)
      citation = item["citation"]
      item.merge(
        "status" => "possible",
        "enrichment" => "ai",
        "signals" => Array(item["signals"]) | ["ai"],
        "citations" => citation ? [citation] : Array(item["citations"])
      )
    end

    def existing_counts
      counts = Hash.new(0)
      Array(extract["items"]).each do |item|
        prefix = prefix_for(item["type"])
        match = item["id"].to_s.match(/-#{prefix}(\d+)\z/)
        counts[prefix] = [counts[prefix], match[1].to_i].max if match
      end
      counts
    end

    def prefix_for(type)
      case type
      when "commitment" then "c"
      when "decision" then "d"
      else "o"
      end
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
