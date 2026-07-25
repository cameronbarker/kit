# frozen_string_literal: true

module Kit
  module Brief
    VERSION = Kit::VERSION
    DEFAULT_VAULT_DIR = Kit::Surface::DEFAULT_VAULT_DIR

    class Error < Kit::Error; end
  end
end

require_relative "brief/report"
require_relative "brief/cli"
