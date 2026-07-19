# frozen_string_literal: true

require "json"
require "optparse"

module Kit::Listen
  class CLI
    PLANNED_COMMANDS = {
      "start" => "Start a background recording session",
      "pause" => "Pause the active recording",
      "resume" => "Resume a paused recording",
      "speakers" => "Show transcript speaker labels",
      "rename-speaker" => "Rename a speaker and re-render"
    }.freeze

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @options = {
        mock: false,
        dry_run: false,
        transcribe: false,
        format: "m4a",
        transcripts_dir: DEFAULT_TRANSCRIPTS_DIR,
        recordings_dir: DEFAULT_RECORDINGS_DIR,
        device: nil,
        json: false
      }
    end

    def run
      command = @argv.shift
      case command
      when "transcribe"
        parse_transcribe_options!
        input = required_input!
        Pipeline.new(input: input, transcripts_dir: @options[:transcripts_dir], mock: @options[:mock]).transcribe
      when "render"
        parse_render_options!
        input = required_input!
        Pipeline.new(input: input, transcripts_dir: @options[:transcripts_dir], mock: false).render
      when "devices"
        parse_devices_options!
        Recorder.list_devices
      when "record"
        parse_record_options!
        title = required_title!
        Recorder.new(
          title: title,
          device: @options[:device],
          format: @options[:format],
          recordings_dir: @options[:recordings_dir],
          transcripts_dir: @options[:transcripts_dir],
          transcribe: @options[:transcribe],
          mock: @options[:mock],
          dry_run: @options[:dry_run]
        ).record
      when "status"
        parse_control_options!("Usage: listen status [options]")
        run_status
      when "latest"
        parse_control_options!("Usage: listen latest [options]")
        run_latest
      when "stop"
        parse_control_options!("Usage: listen stop [options]")
        run_stop
      when *PLANNED_COMMANDS.keys
        print_planned(command)
        2
      when "help", "-h", "--help", nil
        print_help
        0
      when "version", "-v", "--version"
        puts "kit listen #{VERSION}"
        0
      else
        warn "Unknown command: #{command}"
        print_help
        1
      end
    rescue Error => e
      warn "Error: #{e.message}"
      1
    end

    private

    def parse_transcribe_options!
      parse_options!("Usage: kit listen transcribe [options] INPUT") do |opts|
        opts.on("--mock", "Use mock Python worker output (no ML)") { @options[:mock] = true }
        add_transcripts_dir_option!(opts, "Output root (default: transcripts/)")
      end
    end

    def parse_render_options!
      parse_options!("Usage: kit listen render [options] INPUT") do |opts|
        add_transcripts_dir_option!(opts, "Output root (default: transcripts/)")
      end
    end

    def parse_devices_options!
      parse_options!("Usage: kit listen devices")
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?
    end

    def parse_record_options!
      parse_options!("Usage: kit listen record [options] TITLE") do |opts|
        opts.on("--device NAME", "avfoundation audio device name") { |name| @options[:device] = name }
        opts.on("--format FORMAT", SUPPORTED_FORMATS, "Audio format: m4a or wav (default: m4a)") do |format|
          @options[:format] = format
        end
        opts.on("--transcribe", "Transcribe after recording finishes") { @options[:transcribe] = true }
        opts.on("--mock", "With --transcribe, use mock Python worker") { @options[:mock] = true }
        opts.on("--dry-run", "Write placeholder audio + metadata without ffmpeg capture") { @options[:dry_run] = true }
        add_recordings_dir_option!(opts)
        add_transcripts_dir_option!(opts, "Transcripts root when using --transcribe")
      end
    end

    def parse_control_options!(banner)
      parse_options!(banner) do |opts|
        opts.on("--json", "Emit machine-readable JSON") { @options[:json] = true }
        add_recordings_dir_option!(opts)
      end
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?
    end

    def parse_options!(banner)
      parser = OptionParser.new do |opts|
        opts.banner = banner
        yield opts if block_given?
        add_help_option!(opts)
      end
      parser.parse!(@argv)
    end

    def run_status
      state = RecordingState.new(@options[:recordings_dir])
      state.recover_if_stale!
      payload = state.to_status_hash
      if @options[:json]
        puts JSON.pretty_generate(payload)
      else
        puts "phase=#{payload['phase']} pid=#{payload['recorder_pid'].inspect} title=#{payload['title'].inspect}"
      end
      0
    end

    def run_latest
      payload = RecordingState.latest_payload(@options[:recordings_dir])
      if @options[:json]
        puts JSON.pretty_generate(payload)
      elsif payload["found"]
        puts "latest=#{payload['metadata_path']}"
      else
        puts "latest=(none)"
      end
      0
    end

    def run_stop
      state = RecordingState.new(@options[:recordings_dir])
      payload = state.stop!
      if @options[:json]
        puts JSON.pretty_generate(payload)
      else
        puts "stop=#{payload['action']} phase=#{payload['phase']} #{payload['message']}"
      end
      0
    end

    def print_planned(command)
      warn "kit listen #{command} is planned but not implemented yet."
      warn PLANNED_COMMANDS.fetch(command)
      warn "Run `kit listen help` to see the current listen command surface."
    end

    def add_help_option!(opts)
      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end

    def add_transcripts_dir_option!(opts, description)
      opts.on("--transcripts-dir DIR", description) do |dir|
        @options[:transcripts_dir] = File.expand_path(dir)
      end
    end

    def add_recordings_dir_option!(opts)
      opts.on("--recordings-dir DIR", "Recordings root (default: recordings/)") do |dir|
        @options[:recordings_dir] = File.expand_path(dir)
      end
    end

    def required_input!
      required_arg!("INPUT path")
    end

    def required_title!
      required_arg!("TITLE")
    end

    def required_arg!(label)
      value = @argv.shift
      raise Error, "missing #{label}" if value.nil? || value.strip.empty?
      raise Error, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      value
    end

    def print_help
      puts <<~HELP
        kit listen #{VERSION}

        Implemented commands:
          devices                     List macOS avfoundation audio input devices
          record [options] TITLE      Record in the foreground from an audio device
          status [--json]             Show recording lifecycle state
          latest [--json]             Show newest recording metadata
          stop [--json]               Stop the active recorder process
          transcribe [--mock] INPUT   Transcribe a meeting audio/video file
          render INPUT                Re-render Markdown/JSON from existing raw JSON
          help                        Show this help
          version                     Show version

        Planned lifecycle commands:
          start [options] TITLE        Start a background recording session
          pause [options]              Pause the active recording
          resume [options]             Resume a paused recording
          speakers [options] INPUT     Show transcript speaker labels
          rename-speaker INPUT RAW NAME
                                      Rename a speaker and re-render
      HELP

      puts <<~HELP

        Record options:
          --device NAME               Audio device (or set #{AUDIO_DEVICE_ENV})
          --format m4a|wav            Output format (default: m4a)
          --transcribe                Run transcription after recording
          --mock                      With --transcribe, skip ML (mock worker)
          --dry-run                   Placeholder capture for tests/CI
          --recordings-dir DIR        Default: recordings/
          --transcripts-dir DIR       Used with --transcribe

        Control options:
          --json                      Machine-readable JSON for status/latest/stop
          --recordings-dir DIR        Default: recordings/

        Target workflow:
          kit listen start "Platform Sync" --transcribe-on-stop
          kit listen pause
          kit listen resume
          kit listen stop --transcribe
          kit listen transcribe latest
          kit listen render latest

        Examples:
          kit listen devices
          kit listen record "Platform Sync" --device "Loopback Audio"
          kit listen record "Platform Sync" --format m4a --transcribe
          kit listen status --json
          kit listen latest --json
          kit listen stop --json
          kit listen transcribe --mock path/to/meeting.m4a
          kit listen transcribe path/to/meeting.m4a
          kit listen render path/to/meeting.m4a
      HELP
    end
  end
end
