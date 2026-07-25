# frozen_string_literal: true

module Kit
  module Notice
    VERSION = Kit::VERSION
    DEFAULT_TRANSCRIPTS_DIR = File.expand_path("../../transcripts", __dir__)
    DEFAULT_EXTRACTS_DIR = File.expand_path("../../extracts", __dir__)

    class Error < Kit::Error; end
  end
end

require_relative "notice/extractor"
require_relative "notice/artifacts"
require_relative "notice/cli"
