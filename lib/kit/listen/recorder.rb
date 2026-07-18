# frozen_string_literal: true

require "fileutils"
require "open3"
require "time"
require "yaml"

module Kit::Listen
  class Recorder
    attr_reader :title, :format, :recordings_dir, :transcripts_dir, :transcribe_after, :mock, :dry_run

    def self.list_devices
      raw = Ffmpeg.list_devices_output
      lines = Ffmpeg.useful_device_lines(raw)
      if lines.empty?
        puts "No AVFoundation audio device lines found."
        puts "Raw ffmpeg output:"
        puts raw
      else
        puts lines
      end
      0
    end

    def self.resolve_device(cli_device)
      device = cli_device.to_s.strip
      return device unless device.empty?

      env_device = ENV[AUDIO_DEVICE_ENV].to_s.strip
      return env_device unless env_device.empty?

      legacy_env_device = ENV[LEGACY_AUDIO_DEVICE_ENV].to_s.strip
      return legacy_env_device unless legacy_env_device.empty?

      raise Error, <<~MSG.strip
        No audio device configured.
        Pass --device "Loopback Audio" or set #{AUDIO_DEVICE_ENV}.
        List devices with: kit listen devices
      MSG
    end

    def initialize(
      title:,
      device: nil,
      format: "m4a",
      recordings_dir: DEFAULT_RECORDINGS_DIR,
      transcripts_dir: DEFAULT_TRANSCRIPTS_DIR,
      transcribe: false,
      mock: false,
      dry_run: false,
      now: nil
    )
      @title = title.to_s.strip
      raise Error, "missing TITLE" if @title.empty?

      @device = device
      @format = format.to_s
      raise Error, "unsupported format: #{@format} (use m4a or wav)" unless SUPPORTED_FORMATS.include?(@format)

      @recordings_dir = File.expand_path(recordings_dir)
      @transcripts_dir = File.expand_path(transcripts_dir)
      @transcribe_after = transcribe
      @mock = mock
      @dry_run = dry_run
      @now = now || Time.now
    end

    def device
      @resolved_device ||= self.class.resolve_device(@device)
    end

    def slug
      @slug ||= Util.slugify(title)
    end

    def timestamp
      @timestamp ||= @now.strftime("%Y%m%d-%H%M%S")
    end

    def basename
      "#{timestamp}-#{slug}"
    end

    def recording_path
      File.join(recordings_dir, "#{basename}.#{format}")
    end

    def metadata_path
      File.join(recordings_dir, "#{basename}.yml")
    end

    def ffmpeg_args
      ["ffmpeg", "-f", "avfoundation", "-i", ":#{device}"] + codec_args + [recording_path]
    end

    def record
      FileUtils.mkdir_p(recordings_dir)
      started_at = @now
      state = RecordingState.new(recordings_dir)
      state.recover_if_stale!

      if state.active_recording?
        raise Error, "a recording is already in progress (pid #{state.read['recorder_pid']})"
      end

      Ffmpeg.ensure_available! unless dry_run

      state.begin_recording!(
        title: title,
        source_device: device,
        recording_path: recording_path,
        metadata_path: metadata_path,
        started_at: started_at
      )

      begin
        if dry_run
          File.write(recording_path, "dry-run-audio")
          ended_at = Time.now
        else
          puts "Recording #{title.inspect} from #{device.inspect} -> #{recording_path}"
          puts "Press Ctrl-C to stop."
          ended_at = run_ffmpeg!(started_at)
        end

        raise Error, "recording file missing or empty: #{recording_path}" unless usable_recording?

        metadata = build_metadata(started_at: started_at, ended_at: ended_at)
        write_metadata!(metadata)

        if transcribe_after
          pipeline = Pipeline.new(input: recording_path, transcripts_dir: transcripts_dir, mock: mock)
          pipeline.transcribe
          metadata["transcribed"] = true
          metadata["transcript_json"] = pipeline.final_json_path
          metadata["transcript_md"] = pipeline.markdown_path
          write_metadata!(metadata)
        end

        state.complete!(ended_at: ended_at)
        print_success(metadata)
        0
      rescue StandardError => e
        state.fail!(error: e.message, ended_at: Time.now)
        raise
      end
    end

    private

    def codec_args
      case format
      when "wav"
        ["-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le"]
      when "m4a"
        ["-c:a", "aac", "-b:a", "128k"]
      else
        []
      end
    end

    def run_ffmpeg!(started_at)
      ended_at = nil
      stop = nil
      pending_stop = false
      old_int = trap("INT") { stop ? stop.call : pending_stop = true }
      old_term = trap("TERM") { stop ? stop.call : pending_stop = true }

      begin
        Open3.popen3(*ffmpeg_args) do |stdin, stdout, stderr, wait_thr|
          stopping = false
          stop = lambda do
            return if stopping

            stopping = true
            begin
              stdin.write("q\n")
              stdin.flush
            rescue Errno::EPIPE, IOError
              # ffmpeg already exited
            end

            pid = wait_thr.pid
            begin
              Process.kill("INT", pid) if pid
            rescue Errno::ESRCH
              # already gone
            end
          end
          stop.call if pending_stop

          stderr_thread = Thread.new { stderr.read }
          stdout_thread = Thread.new { stdout.read }
          status = wait_thr.value
          ended_at = Time.now
          err = stderr_thread.value.to_s
          out = stdout_thread.value.to_s
          warn err unless err.strip.empty?

          unless usable_recording?
            detail = [out, err].map { |s| s.to_s.strip }.reject(&:empty?).join("\n")
            raise Error, "ffmpeg recording failed (exit #{status.exitstatus}).#{detail.empty? ? '' : "\n#{detail}"}"
          end
        end
      ensure
        trap("INT", old_int || "DEFAULT")
        trap("TERM", old_term || "DEFAULT")
      end
      ended_at || Time.now
    end

    def usable_recording?
      File.file?(recording_path) && File.size(recording_path).positive?
    end

    def build_metadata(started_at:, ended_at:)
      duration = (ended_at - started_at).to_f.round(3)
      {
        "title" => title,
        "source_device" => device,
        "recording_file" => recording_path,
        "started_at" => started_at.iso8601,
        "ended_at" => ended_at.iso8601,
        "duration_seconds" => duration,
        "format" => format,
        "transcribed" => false
      }
    end

    def write_metadata!(metadata)
      File.write(metadata_path, YAML.dump(metadata))
    end

    def print_success(metadata)
      puts "OK (record): #{basename}"
      puts "  audio: #{recording_path}"
      puts "  meta:  #{metadata_path}"
      if metadata["transcribed"]
        puts "  json:  #{metadata['transcript_json']}"
        puts "  md:    #{metadata['transcript_md']}"
      end
    end
  end
end
