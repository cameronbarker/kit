# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"

module Kit::Listen
  class ChunkedSession
    METADATA_FILENAME = "session.yml"

    attr_reader :title, :device, :recordings_dir, :transcripts_dir, :chunk_seconds, :mock, :dry_run, :now

    def self.metadata_path_for(recordings_dir, session_id)
      File.join(File.expand_path(recordings_dir), session_id, METADATA_FILENAME)
    end

    def self.active?(recordings_dir)
      state = RecordingState.new(recordings_dir).read
      state["mode"] == "chunked" && state["session_id"]
    end

    def self.status(recordings_dir)
      state = RecordingState.new(recordings_dir)
      current = state.read
      if current["mode"] == "chunked" && current["session_id"]
        path = metadata_path_for(recordings_dir, current["session_id"])
        metadata = load_metadata(path)
        if metadata
          metadata = recover_if_stale!(metadata)
          refresh_state_from_metadata!(state, metadata)
        end
      else
        state.recover_if_stale!
      end

      state.to_status_hash
    end

    def self.pause(recordings_dir)
      new(recordings_dir: recordings_dir).pause
    end

    def self.resume(recordings_dir, mock: false, dry_run: false)
      new(recordings_dir: recordings_dir, mock: mock, dry_run: dry_run).resume
    end

    def self.stop(recordings_dir, transcripts_dir: DEFAULT_TRANSCRIPTS_DIR, mock: false, on_progress: nil)
      new(recordings_dir: recordings_dir, transcripts_dir: transcripts_dir, mock: mock).stop(on_progress: on_progress)
    end

    def initialize(
      title: nil,
      device: nil,
      recordings_dir: DEFAULT_RECORDINGS_DIR,
      transcripts_dir: DEFAULT_TRANSCRIPTS_DIR,
      chunk_seconds: DEFAULT_CHUNK_SECONDS,
      mock: false,
      dry_run: false,
      now: nil
    )
      @title = title.to_s.strip
      @device = device
      @recordings_dir = File.expand_path(recordings_dir)
      @transcripts_dir = File.expand_path(transcripts_dir)
      @chunk_seconds = Integer(chunk_seconds)
      raise Error, "chunk seconds must be positive" unless @chunk_seconds.positive?

      @mock = mock
      @dry_run = dry_run
      @now = now || Time.now
    end

    def start
      raise Error, "missing TITLE" if title.empty?

      state = RecordingState.new(recordings_dir)
      state.recover_if_stale!
      if state.active_recording? || chunked_active_state?(state.read)
        raise Error, "a recording session is already active"
      end

      Ffmpeg.ensure_available! unless dry_run
      FileUtils.mkdir_p(chunks_dir)

      metadata = base_metadata.merge(
        "phase" => "recording",
        "recorder_pid" => nil,
        "started_at" => now.iso8601
      )
      write_metadata!(metadata)

      pid = dry_run ? nil : spawn_ffmpeg!(next_chunk_index(metadata))
      metadata["recorder_pid"] = pid
      if dry_run
        write_dry_run_chunk!(1, metadata)
        metadata["chunks"] = chunk_entries
      end
      write_metadata!(metadata)
      write_state!(state, metadata)
      action_payload("started", metadata)
    rescue StandardError => e
      fail_active_session!(e.message)
      raise
    end

    def pause
      state = RecordingState.new(recordings_dir)
      metadata = active_metadata!(state)
      return action_payload("noop", metadata, "session is not recording") unless metadata["phase"] == "recording"

      stop_recorder(metadata)
      metadata["phase"] = "paused"
      metadata["recorder_pid"] = nil
      metadata["chunks"] = chunk_entries(metadata)
      metadata["paused_at"] = Time.now.iso8601
      write_metadata!(metadata)
      write_state!(state, metadata)
      action_payload("paused", metadata)
    end

    def resume
      state = RecordingState.new(recordings_dir)
      metadata = active_metadata!(state)
      return action_payload("noop", metadata, "session is not paused") unless metadata["phase"] == "paused"

      Ffmpeg.ensure_available! unless dry_run || metadata["dry_run"]
      if dry_run || metadata["dry_run"]
        write_dry_run_chunk!(next_chunk_index(metadata), metadata)
        pid = nil
      else
        pid = spawn_ffmpeg!(next_chunk_index(metadata))
      end

      metadata["phase"] = "recording"
      metadata["recorder_pid"] = pid
      metadata["chunks"] = chunk_entries(metadata)
      metadata["resumed_at"] = Time.now.iso8601
      write_metadata!(metadata)
      write_state!(state, metadata)
      action_payload("resumed", metadata)
    end

    def stop(on_progress: nil)
      @on_progress = on_progress
      state = RecordingState.new(recordings_dir)
      return legacy_stop(state) unless self.class.active?(recordings_dir)

      metadata = active_metadata!(state)
      progress("Stopping recorder")
      stop_recorder(metadata) if metadata["phase"] == "recording"
      metadata["phase"] = "transcribing"
      metadata["recorder_pid"] = nil
      metadata["chunks"] = chunk_entries(metadata)
      write_metadata!(metadata)
      write_state!(state, metadata)

      finalize_transcript!(metadata)
      metadata["phase"] = "completed"
      metadata["ended_at"] = Time.now.iso8601
      metadata["latest_error"] = nil
      write_metadata!(metadata)
      write_state!(state, metadata)
      progress("Done")
      action_payload("completed", metadata)
    rescue StandardError => e
      mark_failed!(state, metadata, e.message) if metadata
      raise
    end

    def session_id
      @session_id ||= "#{now.strftime('%Y%m%d-%H%M%S')}-#{Util.slugify(title)}"
    end

    def session_dir
      File.join(recordings_dir, session_id)
    end

    def chunks_dir
      File.join(session_dir, "chunks")
    end

    def metadata_path
      File.join(session_dir, METADATA_FILENAME)
    end

    private

    def self.load_metadata(path)
      return nil unless File.file?(path)

      data = YAML.safe_load(File.read(path))
      data.is_a?(Hash) ? data : nil
    end

    def self.refresh_state_from_metadata!(state, metadata)
      state.write!(
        "mode" => "chunked",
        "phase" => metadata["phase"],
        "recorder_pid" => metadata["recorder_pid"],
        "title" => metadata["title"],
        "source_device" => metadata["source_device"],
        "recording_path" => metadata["session_dir"],
        "metadata_path" => metadata["metadata_path"],
        "started_at" => metadata["started_at"],
        "ended_at" => metadata["ended_at"],
        "latest_error" => metadata["latest_error"],
        "session_id" => metadata["session_id"],
        "chunks_dir" => metadata["chunks_dir"],
        "chunk_count" => Array(metadata["chunks"]).length,
        "transcript_json" => metadata["transcript_json"],
        "transcript_md" => metadata["transcript_md"]
      )
    end

    def self.recover_if_stale!(metadata)
      return metadata unless metadata["phase"] == "recording"
      return metadata if metadata["dry_run"]
      return metadata if RecordingState.alive?(metadata["recorder_pid"])

      pid = metadata["recorder_pid"]
      metadata["phase"] = "error"
      metadata["recorder_pid"] = nil
      metadata["ended_at"] = Time.now.iso8601
      metadata["latest_error"] = "recorder process #{pid.inspect} is no longer running"
      metadata["chunks"] = Dir.glob(File.join(metadata["chunks_dir"], "chunk-*.wav")).sort.each_with_index.map do |path, index|
        { "index" => index + 1, "path" => path, "duration_seconds" => metadata["chunk_seconds"].to_f }
      end
      File.write(metadata["metadata_path"], YAML.dump(metadata))
      metadata
    end

    def base_metadata
      {
        "session_id" => session_id,
        "title" => title,
        "source_device" => Recorder.resolve_device(device),
        "session_dir" => session_dir,
        "chunks_dir" => chunks_dir,
        "metadata_path" => metadata_path,
        "chunk_seconds" => chunk_seconds,
        "format" => "wav",
        "phase" => "idle",
        "recorder_pid" => nil,
        "started_at" => nil,
        "paused_at" => nil,
        "resumed_at" => nil,
        "ended_at" => nil,
        "chunks" => [],
        "transcribed" => false,
        "transcript_json" => nil,
        "transcript_md" => nil,
        "latest_error" => nil,
        "dry_run" => dry_run,
        "mock" => mock
      }
    end

    def chunked_active_state?(payload)
      return false unless payload["mode"] == "chunked" && payload["session_id"]

      %w[recording paused transcribing].include?(payload["phase"])
    end

    def active_metadata!(state)
      current = state.read
      raise Error, "no active chunked listen session" unless current["mode"] == "chunked" && current["session_id"]

      metadata = self.class.load_metadata(self.class.metadata_path_for(recordings_dir, current["session_id"]))
      raise Error, "active session metadata missing" unless metadata

      metadata
    end

    def write_metadata!(metadata)
      FileUtils.mkdir_p(File.dirname(metadata["metadata_path"] || metadata_path))
      File.write(metadata["metadata_path"] || metadata_path, YAML.dump(metadata))
    end

    def write_state!(state, metadata)
      self.class.refresh_state_from_metadata!(state, metadata)
    end

    def fail_active_session!(message)
      path = metadata_path
      return unless File.file?(path)

      metadata = self.class.load_metadata(path)
      return unless metadata

      metadata["phase"] = "error"
      metadata["latest_error"] = message
      metadata["ended_at"] = Time.now.iso8601
      write_metadata!(metadata)
      write_state!(RecordingState.new(recordings_dir), metadata)
    end

    def mark_failed!(state, metadata, message)
      metadata["phase"] = "error"
      metadata["latest_error"] = message
      metadata["ended_at"] = Time.now.iso8601
      metadata["recorder_pid"] = nil
      write_metadata!(metadata)
      write_state!(state, metadata)
    end

    def spawn_ffmpeg!(start_number)
      FileUtils.mkdir_p(chunks_dir)
      process = Process.spawn(
        *ffmpeg_args(start_number),
        out: File::NULL,
        err: File.join(session_dir, "ffmpeg.log")
      )
      Process.detach(process)
      process
    end

    def ffmpeg_args(start_number)
      [
        "ffmpeg",
        "-f", "avfoundation",
        "-i", ":#{Recorder.resolve_device(device)}",
        "-ac", "1",
        "-ar", "16000",
        "-c:a", "pcm_s16le",
        "-f", "segment",
        "-segment_time", chunk_seconds.to_s,
        "-reset_timestamps", "1",
        "-segment_start_number", start_number.to_s,
        File.join(chunks_dir, "chunk-%06d.wav")
      ]
    end

    def stop_recorder(metadata)
      pid = metadata["recorder_pid"]
      return if pid.nil?

      return unless RecordingState.alive?(pid)

      Process.kill("INT", Integer(pid))
      begin
        Process.wait(Integer(pid))
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
    rescue Errno::ESRCH
      nil
    end

    def write_dry_run_chunk!(index, metadata = nil)
      dir = (metadata && metadata["chunks_dir"]) || chunks_dir
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, format("chunk-%06d.wav", index)), "dry-run-audio-#{index}")
    end

    def chunk_entries(metadata = nil)
      paths = Dir.glob(File.join((metadata && metadata["chunks_dir"]) || chunks_dir, "chunk-*.wav")).sort
      paths.each_with_index.map do |path, index|
        {
          "index" => index + 1,
          "path" => path,
          "duration_seconds" => chunk_duration(path)
        }
      end
    end

    def chunk_duration(path)
      return chunk_seconds.to_f if dry_run || File.read(path, 16).start_with?("dry-run")

      stdout, _stderr, status = Open3.capture3(
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path
      )
      return Float(stdout) if status.success? && stdout.to_s.strip.match?(/\A\d+(\.\d+)?\z/)

      chunk_seconds.to_f
    rescue StandardError
      chunk_seconds.to_f
    end

    def next_chunk_index(metadata)
      existing = chunk_entries(metadata).map { |chunk| chunk["index"].to_i }
      existing.empty? ? 1 : existing.max + 1
    end

    def finalize_transcript!(metadata)
      chunks = chunk_entries(metadata)
      raise Error, "no audio chunks recorded" if chunks.empty?

      FileUtils.mkdir_p(File.join(transcripts_dir, "json"))
      FileUtils.mkdir_p(File.join(transcripts_dir, "md"))
      merged_segments = []
      offset = 0.0
      total = chunks.length

      chunks.each_with_index do |chunk, index|
        progress("Transcribing chunk #{index + 1}/#{total}")
        pipeline = Pipeline.new(
          input: chunk["path"],
          transcripts_dir: transcripts_dir,
          mock: mock || metadata["mock"],
          quiet: true,
          on_progress: @on_progress
        )
        silence_stdout { pipeline.transcribe }
        final = JSON.parse(File.read(pipeline.final_json_path))
        Array(final["segments"]).each do |segment|
          merged_segments << segment.merge(
            "start" => segment["start"].to_f + offset,
            "end" => segment["end"].to_f + offset,
            "chunk_index" => chunk["index"],
            "chunk_path" => chunk["path"]
          )
        end
        offset += chunk["duration_seconds"].to_f
      end

      progress("Merging transcript")
      generated_at = Time.now.iso8601
      final_json = File.join(transcripts_dir, "json", "#{metadata['session_id']}.json")
      final_md = File.join(transcripts_dir, "md", "#{metadata['session_id']}.md")
      File.write(
        final_json,
        JSON.pretty_generate(
          "title" => metadata["title"],
          "source_file" => metadata["session_dir"],
          "generated_at" => generated_at,
          "segments" => merged_segments
        ) + "\n"
      )
      File.write(final_md, markdown(metadata, merged_segments, generated_at))

      metadata["chunks"] = chunks
      metadata["transcribed"] = true
      metadata["transcript_json"] = final_json
      metadata["transcript_md"] = final_md
    end

    def progress(message)
      return unless @on_progress

      @on_progress.call(message)
    end

    def markdown(metadata, segments, generated_at)
      lines = []
      lines << "# #{metadata['title']}"
      lines << ""
      lines << "Source: #{metadata['session_dir']}"
      lines << "Generated: #{generated_at}"
      lines << ""
      segments.each do |segment|
        lines << "[#{format_timestamp(segment['start'])}] #{segment['speaker']}: #{segment['text']}"
      end
      lines << ""
      lines.join("\n")
    end

    def format_timestamp(seconds)
      total = seconds.to_f.floor
      hours = total / 3600
      minutes = (total % 3600) / 60
      secs = total % 60
      format("%02d:%02d:%02d", hours, minutes, secs)
    end

    def legacy_stop(state)
      state.stop!
    end

    def silence_stdout
      original = $stdout
      File.open(File::NULL, "w") do |null|
        $stdout = null
        yield
      end
    ensure
      $stdout = original
    end

    def action_payload(action, metadata, message = nil)
      {
        "ok" => true,
        "action" => action,
        "message" => message || action.tr("_", " "),
        "phase" => metadata["phase"],
        "recorder_pid" => metadata["recorder_pid"],
        "session_id" => metadata["session_id"],
        "metadata_path" => metadata["metadata_path"],
        "chunks_dir" => metadata["chunks_dir"],
        "chunk_count" => Array(metadata["chunks"]).length,
        "transcript_json" => metadata["transcript_json"],
        "transcript_md" => metadata["transcript_md"]
      }
    end
  end
end
