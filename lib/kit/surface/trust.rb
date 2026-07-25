# frozen_string_literal: true

module Kit::Surface
  module Trust
    module_function

    def normalize_item(item)
      item.merge(
        "needs_review" => needs_review?(item),
        "rejected" => rejected?(item)
      )
    end

    def rejected?(item)
      REJECTED_STATUSES.include?(item["status"].to_s.strip.downcase)
    end

    def needs_review?(item)
      status = item["status"].to_s.strip.downcase
      owner = item["owner"].to_s.strip.downcase
      bucket = item["bucket"].to_s.strip

      return false if TRUSTED_STATUSES.include?(status)
      return false if REJECTED_STATUSES.include?(status)
      return true if status.empty? || status == "possible"
      return true if bucket == "commitments_unknown"
      return true if owner.empty? || owner == "unknown"

      true
    end
  end
end
