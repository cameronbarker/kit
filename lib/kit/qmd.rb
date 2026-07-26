# frozen_string_literal: true

module Kit
  module Qmd
    VERSION = Kit::VERSION
    DEFAULT_BINARY = "qmd"
    DEFAULT_INDEX = "kit"
    DEFAULT_COLLECTIONS = {
      "transcripts" => File.join(Kit::Env::ROOT, "transcripts", "md"),
      "extracts" => File.join(Kit::Env::ROOT, "extracts", "md"),
      "vault" => ENV.fetch("KIT_VAULT", File.join(Kit::Env::ROOT, "obsidian"))
    }.freeze

    class Error < Kit::Error; end
    class MissingBinaryError < Error; end
  end
end

require_relative "qmd/client"
require_relative "qmd/cli"
