# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/kit"

class Kit::ListenFfmpegTest < Minitest::Test
  def test_useful_device_lines_keeps_audio_section
    raw = <<~RAW
      [AVFoundation indev @ 0x1] AVFoundation video devices:
      [AVFoundation indev @ 0x1] [0] FaceTime HD Camera
      [AVFoundation indev @ 0x1] AVFoundation audio devices:
      [AVFoundation indev @ 0x1] [0] MacBook Pro Microphone
      [AVFoundation indev @ 0x1] [1] Loopback Audio
    RAW

    lines = Kit::Listen::Ffmpeg.useful_device_lines(raw)
    assert_equal 3, lines.length
    assert_match(/AVFoundation audio devices/, lines[0])
    assert_includes lines[1], "MacBook Pro Microphone"
    assert_includes lines[2], "Loopback Audio"
  end
end
