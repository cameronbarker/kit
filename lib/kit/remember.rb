# frozen_string_literal: true

module Kit
  module Remember
    VERSION = Kit::VERSION
    DEFAULT_EXTRACTS_DIR = File.expand_path("../../extracts", __dir__)
    DEFAULT_VAULT_DIR = File.expand_path("../../obsidian", __dir__)

    class Error < Kit::Error; end
  end
end

require_relative "remember/planner"
require_relative "remember/notebook"
require_relative "remember/trust_gate"
require_relative "remember/cli"
