# frozen_string_literal: true

module Kit
  module Surface
    VERSION = Kit::VERSION
    DEFAULT_VAULT_DIR = File.expand_path("../../obsidian", __dir__)
    NOTE_PATHS = [
      ["Commitments", "Commitments.md"],
      ["Open Loops", "Open Loops.md"],
      ["Decisions", "Decisions.md"]
    ].freeze

    TRUSTED_STATUSES = %w[accepted trusted confirmed actionable].freeze
    REJECTED_STATUSES = %w[rejected].freeze

    class Error < Kit::Error; end
  end
end

require_relative "surface/parser"
require_relative "surface/trust"
require_relative "surface/report"
require_relative "surface/cli"
