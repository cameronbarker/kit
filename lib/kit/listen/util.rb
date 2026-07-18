# frozen_string_literal: true

module Kit::Listen
  module Util
    module_function

    def slugify(name)
      slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      slug.empty? ? "meeting" : slug
    end

    def humanize_title(name)
      words = name.to_s.tr("_-", " ").split.map(&:capitalize)
      words.empty? ? "Meeting" : words.join(" ")
    end
  end
end
