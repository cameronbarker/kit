# frozen_string_literal: true

module Kit
  module AI
    class Error < Kit::Error; end

    def self.provider(name = ENV.fetch("KIT_AI_PROVIDER", "off"))
      case name.to_s.strip.downcase
      when "", "off", "none", "false", "0"
        OffProvider.new
      when "mock"
        MockProvider.new
      else
        raise Error, "unsupported KIT_AI_PROVIDER=#{name.inspect}; supported providers: off, mock"
      end
    end
  end
end

require_relative "ai/provider"
require_relative "ai/off_provider"
require_relative "ai/mock_provider"
