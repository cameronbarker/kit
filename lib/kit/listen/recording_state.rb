# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "yaml"

module Kit::Listen
  class RecordingState
    STATE_FILENAME = ".recording-state.json"
    STATUS_KEYS = %w[
      phase
      recorder_pid
      title
      source_device
      recording_path
      metadata_path
      started_at
      ended_at
      latest_error
    ].freeze

    attr_reader :recordings_dir

    def self.alive?(pid)
      return false if pid.nil?

      pid = Integer(pid)
      Process.kill(0, pid)
      true
    rescue ArgumentError, Errno::ESRCH, Errno::EPERM, TypeError
      false
    end

    def self.latest_metadata(recordings_dir)
      dir = File.expand_path(recordings_dir)
      paths = Dir.glob(File.join(dir, "*.yml")).sort
      return nil if paths.empty?

      path = paths.last
      data = YAML.safe_load(File.read(path))
      data = {} unless data.is_a?(Hash)
      { "found" => true, "metadata_path" => path, "recording" => data }
    end

    def self.latest_payload(recordings_dir)
      latest = latest_metadata(recordings_dir)
      return { "found" => false, "metadata_path" => nil, "recording" => nil } if latest.nil?

      latest
    end

    def initialize(recordings_dir = DEFAULT_RECORDINGS_DIR)
      @recordings_dir = File.expand_path(recordings_dir)
    end

    def path
      File.join(recordings_dir, STATE_FILENAME)
    end

    def read
      return idle_defaults unless File.file?(path)

      data = JSON.parse(File.read(path))
      merge_defaults(data)
    rescue JSON::ParserError
      idle_defaults.merge("phase" => "error", "latest_error" => "corrupt recording state file")
    end

    def write!(attrs)
      FileUtils.mkdir_p(recordings_dir)
      payload = merge_defaults(attrs)
      tmp = File.join(recordings_dir, ".recording-state.#{Process.pid}.#{Thread.current.object_id}.tmp")
      File.write(tmp, JSON.pretty_generate(payload) + "\n")
      File.rename(tmp, path)
      payload
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def begin_recording!(title:, source_device:, recording_path:, metadata_path:, started_at:, recorder_pid: Process.pid)
      write!(
        "phase" => "recording",
        "recorder_pid" => Integer(recorder_pid),
        "title" => title,
        "source_device" => source_device,
        "recording_path" => recording_path,
        "metadata_path" => metadata_path,
        "started_at" => iso8601(started_at),
        "ended_at" => nil,
        "latest_error" => nil
      )
    end

    def complete!(ended_at: Time.now)
      current = read
      write!(
        current.merge(
          "phase" => "completed",
          "recorder_pid" => nil,
          "ended_at" => iso8601(ended_at),
          "latest_error" => nil
        )
      )
    end

    def fail!(error:, ended_at: Time.now)
      current = read
      write!(
        current.merge(
          "phase" => "error",
          "recorder_pid" => nil,
          "ended_at" => iso8601(ended_at),
          "latest_error" => error.to_s
        )
      )
    end

    def recover_if_stale!
      current = read
      return current unless current["phase"] == "recording"

      pid = current["recorder_pid"]
      return current if self.class.alive?(pid)

      stale = write!(
        current.merge(
          "phase" => "stale",
          "recorder_pid" => nil,
          "latest_error" => "recorder process #{pid.inspect} is no longer running"
        )
      )

      recording_path = stale["recording_path"]
      metadata_path = stale["metadata_path"]
      usable_audio = recording_path && File.file?(recording_path) && File.size(recording_path).positive?
      has_metadata = metadata_path && File.file?(metadata_path)

      if usable_audio && has_metadata
        write!(
          stale.merge(
            "phase" => "completed",
            "ended_at" => stale["ended_at"] || Time.now.iso8601,
            "latest_error" => "recovered stale recording state; recorder process exited unexpectedly"
          )
        )
      else
        write!(
          stale.merge(
            "phase" => "error",
            "ended_at" => stale["ended_at"] || Time.now.iso8601,
            "latest_error" => "stale recording state: recorder process gone without usable artifacts"
          )
        )
      end
    end

    def active_recording?
      current = read
      current["phase"] == "recording" && self.class.alive?(current["recorder_pid"])
    end

    def to_status_hash
      merge_defaults(read).slice(*STATUS_KEYS)
    end

    def stop!
      before = read
      was_recording_claim = before["phase"] == "recording"
      current = recover_if_stale!

      if was_recording_claim && current["phase"] != "recording"
        return stop_result(
          action: "recovered_stale",
          message: current["latest_error"] || "recovered stale recording state",
          phase: current["phase"],
          recorder_pid: nil
        )
      end

      unless current["phase"] == "recording" && self.class.alive?(current["recorder_pid"])
        return stop_result(
          action: "noop",
          message: "no active recording",
          phase: current["phase"],
          recorder_pid: current["recorder_pid"]
        )
      end

      pid = Integer(current["recorder_pid"])
      begin
        Process.kill("INT", pid)
      rescue Errno::ESRCH
        recovered = recover_if_stale!
        return stop_result(
          action: "recovered_stale",
          message: recovered["latest_error"] || "recorder process already exited",
          phase: recovered["phase"],
          recorder_pid: nil
        )
      end

      stop_result(
        action: "signaled",
        message: "sent INT to recorder process #{pid}",
        phase: "recording",
        recorder_pid: pid
      )
    end

    private

    def idle_defaults
      {
        "phase" => "idle",
        "recorder_pid" => nil,
        "title" => nil,
        "source_device" => nil,
        "recording_path" => nil,
        "metadata_path" => nil,
        "started_at" => nil,
        "ended_at" => nil,
        "latest_error" => nil
      }
    end

    def merge_defaults(attrs)
      idle_defaults.merge(attrs.transform_keys(&:to_s).slice(*STATUS_KEYS))
    end

    def iso8601(value)
      case value
      when nil then nil
      when String then value
      when Time then value.iso8601
      else value.to_s
      end
    end

    def stop_result(action:, message:, phase:, recorder_pid:)
      {
        "ok" => true,
        "action" => action,
        "message" => message,
        "phase" => phase,
        "recorder_pid" => recorder_pid
      }
    end
  end
end
