# frozen_string_literal: true

module Kit
  class Retrieval
    DEFAULT_LIMIT = 5

    attr_reader :client, :mode, :collection, :limit

    def initialize(client: Kit::Qmd::Client.new, mode: "query", collection: nil, limit: DEFAULT_LIMIT)
      @client = client
      @mode = mode.to_s == "search" ? "search" : "query"
      @collection = clean(collection)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
    end

    def retrieve(query)
      text = clean(query)
      return unavailable("missing retrieval query") unless text

      result = client.public_send(mode, text, collection: collection, limit: limit, json: true)
      unless result.success?
        return unavailable(result.stderr.to_s.strip.empty? ? "qmd #{mode} failed" : result.stderr.to_s.strip)
      end

      {
        "available" => true,
        "mode" => mode,
        "collection" => collection,
        "query" => text,
        "hits" => normalize_hits(result.json),
        "warnings" => []
      }
    rescue Kit::Qmd::MissingBinaryError, Kit::Qmd::Error => e
      unavailable(e.message)
    end

    def normalize_hits(raw)
      values = case raw
               when Array then raw
               when Hash
                 raw["results"] || raw["hits"] || raw["documents"] || []
               else
                 []
               end

      Array(values).map { |hit| normalize_hit(hit) }.compact
    end

    private

    def normalize_hit(hit)
      return nil unless hit.is_a?(Hash)

      path = first_present(hit, "path", "filepath", "file", "filename", "id")
      {
        "path" => path,
        "docid" => first_present(hit, "docid", "doc_id", "id"),
        "collection" => first_present(hit, "collection", "collection_name"),
        "score" => numeric(first_present(hit, "score", "rrf_score", "rank_score")),
        "title" => first_present(hit, "title", "heading", "name"),
        "snippet" => first_present(hit, "snippet", "text", "content", "excerpt", "preview"),
        "context" => first_present(hit, "context", "document_context"),
        "source" => first_present(hit, "source", "uri"),
        "raw" => hit
      }
    end

    def unavailable(message)
      {
        "available" => false,
        "mode" => mode,
        "collection" => collection,
        "query" => nil,
        "hits" => [],
        "warnings" => [message]
      }
    end

    def first_present(hash, *keys)
      keys.each do |key|
        value = hash[key]
        next if value.nil?

        text = value.is_a?(String) ? value.strip : value
        return text unless text.respond_to?(:empty?) && text.empty?
      end
      nil
    end

    def numeric(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def clean(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
