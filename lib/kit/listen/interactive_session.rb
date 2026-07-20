# frozen_string_literal: true

require "io/console"
require "yaml"

module Kit::Listen
  class InteractiveSession
    HELP_LINE = "[p] pause/resume   [s] stop   Ctrl+C stop"

    def initialize(
      session:,
      recordings_dir: DEFAULT_RECORDINGS_DIR,
      transcripts_dir: DEFAULT_TRANSCRIPTS_DIR,
      input: $stdin,
      output: $stdout,
      key_source: nil,
      sleep: ->(seconds) { Kernel.sleep(seconds) },
      now: -> { Time.now }
    )
      @session = session
      @recordings_dir = File.expand_path(recordings_dir)
      @transcripts_dir = File.expand_path(transcripts_dir)
      @input = input
      @output = output
      @key_source = key_source
      @sleep = sleep
      @now = now
      @started_at = nil
      @stopped = false
      @pulse = false
    end

    def self.interactive?(json:, detach:, stdin: $stdin)
      !json && !detach && stdin.tty?
    end

    def run
      @session.start
      @started_at = @now.call
      device = payload_device
      title = @session.title

      @output.puts "Listening: #{title} · #{device}"
      @output.puts "  #{HELP_LINE}"
      @output.puts

      previous_int = Signal.trap("INT") { @stopped = true }
      begin
        with_raw_terminal do
          until @stopped
            status = ChunkedSession.status(@recordings_dir)
            phase = status["phase"].to_s

            if phase == "error"
              clear_status_line
              raise Error, status["latest_error"] || "recording failed"
            end

            if phase == "recording" && status["recorder_pid"] && !RecordingState.alive?(status["recorder_pid"])
              clear_status_line
              raise Error, "recorder process #{status['recorder_pid']} is no longer running"
            end

            render_status(status)
            handle_key(read_key)
            @sleep.call(0.25) unless @stopped
          end
        end
      ensure
        Signal.trap("INT", previous_int || "DEFAULT")
      end

      clear_status_line
      @output.puts
      @output.puts "Stopping and transcribing…"
      result = ChunkedSession.stop(
        @recordings_dir,
        transcripts_dir: @transcripts_dir,
        mock: @session.mock,
        on_progress: ->(message) { @output.puts "  … #{message}" }
      )
      print_completion(result)
      0
    end

    private

    def payload_device
      meta_path = File.join(@session.session_dir, ChunkedSession::METADATA_FILENAME)
      return Recorder.resolve_device(@session.device) unless File.file?(meta_path)

      data = YAML.safe_load(File.read(meta_path))
      data.is_a?(Hash) ? data["source_device"] : Recorder.resolve_device(@session.device)
    rescue StandardError
      Recorder.resolve_device(@session.device)
    end

    def render_status(status)
      @pulse = !@pulse
      phase = status["phase"].to_s
      chunks = live_chunk_count(status)
      elapsed = format_elapsed(@now.call - @started_at)

      indicator =
        case phase
        when "paused"
          "❚❚ PAUSED"
        else
          "#{@pulse ? '●' : '○'} REC"
        end

      title = status["title"] || @session.title
      device = status["source_device"] || "?"
      line = "#{indicator}  #{elapsed}  #{title} · #{device} · chunks #{chunks}"
      @output.print "\r\e[K#{line}"
      @output.flush
    end

    def live_chunk_count(status)
      dir = status["chunks_dir"]
      if dir && File.directory?(dir)
        return Dir.glob(File.join(dir, "chunk-*.wav")).count { |path| File.size?(path).to_i.positive? }
      end

      status["chunk_count"].to_i
    end

    def handle_key(key)
      return if key.nil?

      case key
      when "p", "P"
        toggle_pause
      when "s", "S", "\r", "\n"
        @stopped = true
      when "\u0003" # Ctrl+C
        @stopped = true
      end
    end

    def toggle_pause
      status = ChunkedSession.status(@recordings_dir)
      case status["phase"]
      when "recording"
        ChunkedSession.pause(@recordings_dir)
      when "paused"
        ChunkedSession.resume(
          @recordings_dir,
          mock: @session.mock,
          dry_run: @session.dry_run
        )
      end
    end

    def read_key
      return @key_source.call if @key_source

      begin
        @input.read_nonblock(1)
      rescue IO::WaitReadable, EOFError
        nil
      end
    end

    def with_raw_terminal
      return yield unless @input.respond_to?(:tty?) && @input.tty? && @key_source.nil?

      saved = `stty -g`.to_s.strip
      system("stty", "-echo", "-icanon", "min", "1", "time", "0")
      yield
    ensure
      system("stty", saved) if saved && !saved.empty?
    end

    def clear_status_line
      @output.print "\r\e[K"
      @output.flush
    end

    def format_elapsed(seconds)
      total = [seconds.to_i, 0].max
      minutes = total / 60
      secs = total % 60
      format("%02d:%02d", minutes, secs)
    end

    def print_completion(result)
      md = result["transcript_md"]
      json = result["transcript_json"]
      @output.puts
      @output.puts "Transcript ready."
      @output.puts "  md:   #{md}" if md
      @output.puts "  json: #{json}" if json

      return unless md && File.file?(md)

      preview = File.readlines(md).grep(/^\[[0-9]/).first(5)
      return if preview.empty?

      @output.puts
      @output.puts "Preview:"
      preview.each { |line| @output.puts "  #{line.chomp}" }
    end
  end
end
