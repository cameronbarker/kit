# frozen_string_literal: true

module Kit
  module Prepare
    VERSION = Kit::VERSION
    DEFAULT_VAULT_DIR = Kit::Surface::DEFAULT_VAULT_DIR
    TRUSTED_STATUSES = Kit::Surface::TRUSTED_STATUSES
    REJECTED_STATUSES = Kit::Surface::REJECTED_STATUSES

    class Error < Kit::Error; end
  end
end

require_relative "prepare/pack"
require_relative "prepare/cli"
