# frozen_string_literal: true

module Kit
  module Listen
    VERSION = Kit::VERSION
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_TRANSCRIPTS_DIR = File.join(ROOT, "transcripts")
    DEFAULT_RECORDINGS_DIR = File.join(ROOT, "recordings")
    PYTHON_WORKER = File.join(__dir__, "listen", "python", "transcribe.py")
    AUDIO_DEVICE_ENV = "KIT_LISTEN_AUDIO_DEVICE"
    LEGACY_AUDIO_DEVICE_ENV = "LEADERSHIP_TRANSCRIPTS_AUDIO_DEVICE"
    SUPPORTED_FORMATS = %w[m4a wav].freeze

    class Error < Kit::Error; end
  end
end

require_relative "listen/util"
require_relative "listen/ffmpeg"
require_relative "listen/pipeline"
require_relative "listen/recording_state"
require_relative "listen/recorder"
require_relative "listen/cli"
