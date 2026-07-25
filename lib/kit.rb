# frozen_string_literal: true

module Kit
  VERSION = "0.1.0"

  class Error < StandardError; end
end

require_relative "kit/env"
Kit::Env.load!

require_relative "kit/notifications"
require_relative "kit/listen"
require_relative "kit/notice"
require_relative "kit/remember"
require_relative "kit/app_bridge"
require_relative "kit/menubar"
require_relative "kit/cli"
