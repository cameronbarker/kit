# frozen_string_literal: true

require "open3"

module Kit::Listen
  module Ffmpeg
    module_function

    def ensure_available!
      _stdout, _stderr, status = Open3.capture3("ffmpeg", "-version")
      return if status.success?

      raise Error, <<~MSG.strip
        ffmpeg not found or failed to run.
        Install on macOS with Homebrew: brew install ffmpeg
        Then verify with: ffmpeg -version
      MSG
    end

    def list_devices_output
      ensure_available!
      stdout, stderr, _status = Open3.capture3(
        "ffmpeg",
        "-f", "avfoundation",
        "-list_devices", "true",
        "-i", ""
      )
      [stdout, stderr].map(&:to_s).join("\n")
    end

    def useful_device_lines(raw)
      lines = raw.to_s.lines.map(&:chomp)
      audio_idx = lines.index { |line| line.match?(/AVFoundation\s+audio\s+devices/i) }
      return lines.reject(&:empty?) if audio_idx.nil?

      useful = []
      useful << lines[audio_idx]
      ((audio_idx + 1)...lines.length).each do |i|
        line = lines[i]
        break if line.match?(/AVFoundation\s+video\s+devices/i)

        useful << line
      end
      useful.reject { |line| line.strip.empty? }
    end
  end
end
