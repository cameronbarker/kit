# frozen_string_literal: true

module Kit
  module Reflect
    VERSION = Kit::VERSION
    DEFAULT_VAULT_DIR = Kit::Surface::DEFAULT_VAULT_DIR

    class Error < Kit::Error; end
  end
end

require_relative "reflect/report"
require_relative "reflect/cli"
