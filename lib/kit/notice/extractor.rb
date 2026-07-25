# frozen_string_literal: true

require "time"

module Kit::Notice
  class Extractor
    FIRST_PERSON_COMMITMENT_PATTERNS = [
      /\bi'll\b/i,
      /\bi will\b/i,
      /\bi can\b/i,
      /\bi owe you\b/i,
      /\blet me\b/i,
      /\bget back to you\b/i
    ].freeze

    OTHER_COMMITMENT_PATTERNS = [
      /\b[A-Z][a-z]+ will\b/,
      /\b[A-Z][a-z]+ can\b/,
      /\b[A-Z][a-z]+ is going to\b/i
    ].freeze

    OPEN_LOOP_PATTERNS = [
      /\bwe should\b/i,
      /\bwe need to\b/i,
      /\bcan someone\b/i,
      /\bsomeone needs to\b/i,
      /\bwe(?:'ll| will) revisit\b/i,
      /\brevisit\b/i,
      /\bno owner\b/i,
      /\bunclear\b/i,
      /\bwaiting on\b/i,
      /\bneed to decide\b/i,
      /\blet's decide\b/i
    ].freeze

    DECISION_PATTERNS = [
      /\bwe decided\b/i,
      /\bdecision is\b/i,
      /\bwe(?:'re| are) going with\b/i,
      /\bkeep\b/i,
      /\bdo not\b/i,
      /\bwon't\b/i,
      /\bwill not\b/i
    ].freeze

    attr_reader :payload, :transcript_path, :me

    def initialize(payload:, transcript_path:, me: nil, now: Time.now)
      @payload = payload
      @transcript_path = File.expand_path(transcript_path)
      @me = clean(me)
      @now = now
    end

    def extract
      items = []
      warnings = []
      speakers = segments.map { |segment| segment["speaker"].to_s }.reject(&:empty?).uniq
      warnings << "No --me or KIT_ME supplied; commitment perspective requires human review." if me.nil? && speakers.length > 1

      segments.each do |segment|
        text = clean(segment["text"])
        next if text.nil?

        items << commitment_item(segment, text) if first_person_commitment?(text)
        items << other_named_commitment_item(segment, text) if other_named_commitment?(text)
        items << decision_item(segment, text) if decision?(text)
        items << open_loop_item(segment, text) if open_loop?(text)
      end

      {
        "schema_version" => 1,
        "kind" => "kit_notice_extract",
        "title" => payload["title"].to_s.empty? ? "Untitled Transcript" : payload["title"].to_s,
        "slug" => slug,
        "generated_at" => @now.iso8601,
        "review_required" => true,
        "input" => {
          "transcript_json" => transcript_path,
          "source_file" => payload["source_file"]
        },
        "identity" => {
          "me" => me,
          "perspective" => me.nil? ? "unknown" : "configured"
        },
        "warnings" => warnings,
        "items" => assign_ids(items)
      }
    end

    private

    def segments
      Array(payload["segments"])
    end

    def slug
      File.basename(transcript_path, ".json")
    end

    def clean(value)
      text = value.to_s.gsub(/\s+/, " ").strip
      text.empty? ? nil : text
    end

    def first_person_commitment?(text)
      FIRST_PERSON_COMMITMENT_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def other_named_commitment?(text)
      OTHER_COMMITMENT_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def decision?(text)
      DECISION_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def open_loop?(text)
      OPEN_LOOP_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def commitment_item(segment, text)
      speaker = segment["speaker"].to_s
      bucket = if me.nil?
                 "commitments_unknown"
               elsif speaker == me
                 "commitments_i_made"
               else
                 "commitments_others_made"
               end

      base_item(
        type: "commitment",
        bucket: bucket,
        text: text,
        owner: speaker.empty? ? nil : speaker,
        status: "possible",
        signals: matched_signals(text, FIRST_PERSON_COMMITMENT_PATTERNS),
        segment: segment
      )
    end

    def other_named_commitment_item(segment, text)
      base_item(
        type: "commitment",
        bucket: "commitments_others_made",
        text: text,
        owner: named_owner(text),
        status: "possible",
        signals: matched_signals(text, OTHER_COMMITMENT_PATTERNS),
        segment: segment
      )
    end

    def decision_item(segment, text)
      base_item(
        type: "decision",
        bucket: "decisions",
        text: text,
        owner: nil,
        status: "possible",
        signals: matched_signals(text, DECISION_PATTERNS),
        segment: segment
      )
    end

    def open_loop_item(segment, text)
      base_item(
        type: "open_loop",
        bucket: "open_loops",
        text: text,
        owner: nil,
        status: "possible",
        signals: matched_signals(text, OPEN_LOOP_PATTERNS),
        segment: segment
      )
    end

    def base_item(type:, bucket:, text:, owner:, status:, signals:, segment:)
      {
        "type" => type,
        "bucket" => bucket,
        "text" => text,
        "owner" => owner,
        "status" => status,
        "signals" => signals,
        "citation" => citation(segment, text)
      }
    end

    def citation(segment, text)
      {
        "transcript_path" => transcript_path,
        "speaker" => segment["speaker"],
        "raw_speaker" => segment["raw_speaker"],
        "start" => segment["start"],
        "end" => segment["end"],
        "timestamp" => format_timestamp(segment["start"]),
        "quote" => text
      }
    end

    def matched_signals(text, patterns)
      patterns.filter_map { |pattern| text[pattern]&.strip }.uniq
    end

    def named_owner(text)
      match = text.match(/\b([A-Z][a-z]+) (?:will|can|is going to)\b/)
      match && match[1]
    end

    def assign_ids(items)
      counts = Hash.new(0)
      items.map do |item|
        prefix = case item["type"]
                 when "commitment" then "c"
                 when "decision" then "d"
                 else "o"
                 end
        counts[prefix] += 1
        item.merge("id" => "#{slug}-#{prefix}#{format('%03d', counts[prefix])}")
      end
    end

    def format_timestamp(seconds)
      total = seconds.to_f.floor
      hours = total / 3600
      minutes = (total % 3600) / 60
      secs = total % 60
      format("%02d:%02d:%02d", hours, minutes, secs)
    end
  end
end
