# frozen_string_literal: true

module Kit
  module Followup
    VERSION = Kit::VERSION
    DEFAULT_VAULT_DIR = Kit::Surface::DEFAULT_VAULT_DIR

    class Error < Kit::Error; end
  end
end

require_relative "followup/report"
require_relative "followup/cli"
