# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../../lib/kit"

class Kit::ListenInteractiveSessionTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("kit-interactive-")
    @recordings_dir = File.join(@tmpdir, "recordings")
    @transcripts_dir = File.join(@tmpdir, "transcripts")
    @output = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_interactive_predicate
    assert Kit::Listen::InteractiveSession.interactive?(json: false, detach: false, stdin: fake_tty(true))
    refute Kit::Listen::InteractiveSession.interactive?(json: true, detach: false, stdin: fake_tty(true))
    refute Kit::Listen::InteractiveSession.interactive?(json: false, detach: true, stdin: fake_tty(true))
    refute Kit::Listen::InteractiveSession.interactive?(json: false, detach: false, stdin: fake_tty(false))
  end

  def test_interactive_session_stop_key_runs_progress_and_transcript
    session = Kit::Listen::ChunkedSession.new(
      title: "Interactive Demo",
      device: "Loopback Audio",
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      dry_run: true
    )

    keys = ["s"]
    status = Kit::Listen::InteractiveSession.new(
      session: session,
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      output: @output,
      key_source: -> { keys.shift },
      sleep: ->(_seconds) {},
      now: -> { Time.at(1_700_000_000) }
    ).run

    assert_equal 0, status
    text = @output.string
    assert_match(/Listening: Interactive Demo/, text)
    assert_match(/Stopping and transcribing/, text)
    assert_match(/Stopping recorder/, text)
    assert_match(/Transcribing chunk 1\/1/, text)
    assert_match(/Merging transcript/, text)
    assert_match(/Done/, text)
    assert_match(/Transcript ready/, text)
    assert_match(/Preview:/, text)

    state = Kit::Listen::ChunkedSession.status(@recordings_dir)
    assert_equal "completed", state["phase"]
  end

  def test_interactive_session_pause_then_stop
    session = Kit::Listen::ChunkedSession.new(
      title: "Pause Demo",
      device: "Loopback Audio",
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      dry_run: true
    )

    keys = ["p", "p", "s"]
    Kit::Listen::InteractiveSession.new(
      session: session,
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      output: @output,
      key_source: -> { keys.shift },
      sleep: ->(_seconds) {},
      now: -> { Time.at(1_700_000_000) }
    ).run

    assert_match(/Transcript ready/, @output.string)
  end

  def test_stop_progress_callback_from_chunked_session
    session = Kit::Listen::ChunkedSession.new(
      title: "Progress Demo",
      device: "Loopback Audio",
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      dry_run: true
    )
    session.start

    messages = []
    payload = Kit::Listen::ChunkedSession.stop(
      @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      on_progress: ->(message) { messages << message }
    )

    assert_equal "completed", payload["phase"]
    assert_includes messages, "Stopping recorder"
    assert_includes messages, "Transcribing chunk 1/1"
    assert_includes messages, "Merging transcript"
    assert_includes messages, "Done"

    final = Kit::Listen::ChunkedSession.status(@recordings_dir)
    assert_nil final["progress_message"]
  end

  def test_stop_persists_progress_message_to_status
    session = Kit::Listen::ChunkedSession.new(
      title: "Status Progress",
      device: "Loopback Audio",
      recordings_dir: @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      dry_run: true
    )
    session.start

    captured = []
    Kit::Listen::ChunkedSession.stop(
      @recordings_dir,
      transcripts_dir: @transcripts_dir,
      mock: true,
      on_progress: lambda { |message|
        captured << [
          message,
          Kit::Listen::ChunkedSession.status(@recordings_dir)["progress_message"]
        ]
      }
    )

    assert_includes captured, ["Stopping recorder", "Stopping recorder"]
    assert captured.any? { |message, persisted| message == "Transcribing chunk 1/1" && persisted == "Transcribing chunk 1/1" }
    assert_nil Kit::Listen::ChunkedSession.status(@recordings_dir)["progress_message"]
  end

  private

  def fake_tty(value)
    io = StringIO.new
    io.define_singleton_method(:tty?) { value }
    io
  end
end
