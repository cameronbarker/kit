# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"

module Kit::Listen
  class Pipeline
    PROGRESS_PREFIX = "kit-listen:"

    attr_reader :input_path, :transcripts_dir, :mock

    def initialize(input:, transcripts_dir: DEFAULT_TRANSCRIPTS_DIR, mock: false, quiet: false, on_progress: nil)
      @input_path = File.expand_path(input)
      @transcripts_dir = File.expand_path(transcripts_dir)
      @mock = mock
      @quiet = quiet
      @on_progress = on_progress
    end

    def transcribe
      validate_input!
      ensure_directories!
      run_python_worker!
      finalize_from_raw!
      print_success("transcribe") unless @quiet
      0
    end

    def render
      validate_input!
      ensure_directories!
      raise Error, "raw JSON not found: #{raw_json_path}" unless File.file?(raw_json_path)

      finalize_from_raw!
      print_success("render") unless @quiet
      0
    end

    def slug
      @slug ||= Util.slugify(File.basename(input_path, ".*"))
    end

    def title
      @title ||= Util.humanize_title(File.basename(input_path, ".*"))
    end

    def raw_json_path
      File.join(transcripts_dir, "raw", "#{slug}.raw.json")
    end

    def final_json_path
      File.join(transcripts_dir, "json", "#{slug}.json")
    end

    def markdown_path
      File.join(transcripts_dir, "md", "#{slug}.md")
    end

    def speaker_map_path
      File.join(transcripts_dir, "maps", "#{slug}.speaker-map.yml")
    end

    def speakers
      validate_input!
      ensure_directories!
      raise Error, "raw JSON not found: #{raw_json_path}" unless File.file?(raw_json_path)

      raw = load_raw_json
      segments = Array(raw["segments"])
      raise Error, "raw JSON missing segments array" unless segments.is_a?(Array)

      map = load_or_create_speaker_map(segments)
      labels = segments.map { |s| s["speaker"].to_s }.reject(&:empty?).uniq.sort
      labels.map do |label|
        {
          "raw_speaker" => label,
          "name" => map.fetch(label, label),
          "samples" => sample_segments(label, segments, limit: 3).map do |segment|
            {
              "timestamp" => format_timestamp(segment["start"]),
              "text" => segment["text"].to_s.strip
            }
          end
        }
      end
    end

    def rename_speaker(raw_speaker, name)
      validate_input!
      ensure_directories!
      raise Error, "raw JSON not found: #{raw_json_path}" unless File.file?(raw_json_path)

      raw = load_raw_json
      segments = Array(raw["segments"])
      raise Error, "raw JSON missing segments array" unless segments.is_a?(Array)

      label = raw_speaker.to_s.strip
      display_name = name.to_s.strip
      raise Error, "missing RAW speaker label" if label.empty?
      raise Error, "missing NAME" if display_name.empty?

      map = load_or_create_speaker_map(segments)
      unless map.key?(label)
        known = map.keys.sort.join(", ")
        raise Error, "unknown speaker label #{label.inspect}#{known.empty? ? '' : " (known: #{known})"}"
      end

      map[label] = display_name
      write_speaker_map!(map, segments)
      finalize_from_raw!
      print_success("rename-speaker") unless @quiet
      0
    end

    private

    def validate_input!
      raise Error, "input file not found: #{input_path}" unless File.file?(input_path)
    end

    def ensure_directories!
      %w[raw json md maps].each do |subdir|
        FileUtils.mkdir_p(File.join(transcripts_dir, subdir))
      end
    end

    def run_python_worker!
      args = [python_executable, PYTHON_WORKER, "--input", input_path, "--output", raw_json_path]
      args << "--mock" if mock

      stdout = +""
      stderr_lines = []
      status = nil

      Open3.popen3(*args) do |stdin, out, err, wait_thr|
        stdin.close
        err_thread = Thread.new do
          err.each_line do |line|
            text = line.strip
            next if text.empty?

            stderr_lines << text
            handle_worker_stderr_line(text)
          end
        end
        stdout = out.read.to_s
        err_thread.join
        status = wait_thr.value
      end

      unless status.success?
        detail = [stdout, stderr_lines.join("\n")].map { |s| s.to_s.strip }.reject(&:empty?).join("\n")
        raise Error, "Python worker failed (exit #{status.exitstatus}).#{detail.empty? ? '' : "\n#{detail}"}"
      end
      raise Error, "Python worker did not create raw JSON: #{raw_json_path}" unless File.file?(raw_json_path)
    end

    def handle_worker_stderr_line(text)
      if text.start_with?(PROGRESS_PREFIX)
        message = text.delete_prefix(PROGRESS_PREFIX).strip
        return if message.empty?

        if @on_progress
          @on_progress.call(message)
        elsif !@quiet
          warn message
        end
        return
      end

      # Drop library noise (Lightning, NNPACK, UserWarning, …) from the UX.
      return if @on_progress || @quiet

      warn text
    end

    def python_executable
      explicit = ENV["PYTHON"].to_s.strip
      return explicit unless explicit.empty?

      venv_python = File.join(ROOT, ".venv", "bin", "python")
      return venv_python if File.executable?(venv_python)

      "python3"
    end

    def finalize_from_raw!
      raw = load_raw_json
      segments = Array(raw["segments"])
      raise Error, "raw JSON missing segments array" unless segments.is_a?(Array)

      speaker_map = load_or_create_speaker_map(segments)
      generated_at = Time.now.iso8601
      normalized = normalize_segments(segments, speaker_map)

      write_final_json(normalized, generated_at)
      write_markdown(normalized, generated_at)
    end

    def load_raw_json
      JSON.parse(File.read(raw_json_path))
    rescue JSON::ParserError => e
      raise Error, "invalid raw JSON at #{raw_json_path}: #{e.message}"
    end

    def load_or_create_speaker_map(segments)
      if File.file?(speaker_map_path)
        map = YAML.safe_load(File.read(speaker_map_path), permitted_classes: [Symbol]) || {}
        raise Error, "speaker map must be a YAML mapping: #{speaker_map_path}" unless map.is_a?(Hash)

        map = map.transform_keys(&:to_s).transform_values(&:to_s)
        append_missing_speaker_map_entries!(map, segments)
        return map
      end

      labels = segments.map { |s| s["speaker"].to_s }.reject(&:empty?).uniq.sort
      map = labels.to_h { |label| [label, label] }
      write_speaker_map!(map, segments)
      map
    end

    def append_missing_speaker_map_entries!(map, segments)
      labels = segments.map { |s| s["speaker"].to_s }.reject(&:empty?).uniq.sort
      missing = labels.reject { |label| map.key?(label) }
      return if missing.empty?

      File.open(speaker_map_path, "a") do |file|
        file.puts
        file.puts "# New speaker labels found in the raw transcript."
        missing.each do |label|
          speaker_map_comments(label, segments).each { |line| file.puts(line) }
          file.puts(yaml_mapping_line(label, label))
          file.puts
          map[label] = label
        end
      end
    end

    def write_speaker_map!(map, segments)
      lines = []
      lines << "# Speaker samples help identify who each raw label refers to."
      lines << "# Edit only the value after the colon, then run:"
      lines << "#   kit listen render #{input_path}"
      lines << ""

      map.keys.sort.each do |label|
        speaker_map_comments(label, segments).each { |line| lines << line }
        lines << yaml_mapping_line(label, map.fetch(label))
        lines << ""
      end

      File.write(speaker_map_path, lines.join("\n") + "\n")
    end

    def speaker_map_comments(label, segments, sample_count: 3)
      lines = ["# #{label} samples:"]
      samples = sample_segments(label, segments, limit: sample_count)
      if samples.empty?
        lines << "# - (no transcript samples found)"
      else
        samples.each do |segment|
          lines << "# - [#{format_timestamp(segment['start'])}] #{comment_text(segment['text'])}"
        end
      end
      lines
    end

    def sample_segments(label, segments, limit:)
      segments.select { |segment| segment["speaker"].to_s == label }
              .sort_by { |segment| segment["start"].to_f }
              .first(limit)
    end

    def comment_text(text)
      cleaned = text.to_s.gsub(/\s+/, " ").strip
      cleaned.length > 100 ? "#{cleaned[0, 97]}..." : cleaned
    end

    def yaml_mapping_line(label, value)
      YAML.dump(label => value).lines.reject { |line| line == "---\n" }.join.chomp
    end

    def normalize_segments(segments, speaker_map)
      segments.map do |segment|
        raw_speaker = segment["speaker"].to_s
        raw_speaker = "UNKNOWN" if raw_speaker.empty?
        mapped = speaker_map.fetch(raw_speaker, raw_speaker)

        {
          "speaker" => mapped,
          "raw_speaker" => raw_speaker,
          "start" => Float(segment.fetch("start")),
          "end" => Float(segment.fetch("end")),
          "text" => segment.fetch("text").to_s.strip
        }
      end
    end

    def write_final_json(segments, generated_at)
      payload = {
        "title" => title,
        "source_file" => input_path,
        "generated_at" => generated_at,
        "segments" => segments
      }
      File.write(final_json_path, JSON.pretty_generate(payload) + "\n")
    end

    def write_markdown(segments, generated_at)
      lines = []
      lines << "# #{title}"
      lines << ""
      lines << "Source: #{input_path}"
      lines << "Generated: #{generated_at}"
      lines << ""

      segments.each do |segment|
        ts = format_timestamp(segment["start"])
        lines << "[#{ts}] #{segment['speaker']}: #{segment['text']}"
      end
      lines << ""

      File.write(markdown_path, lines.join("\n"))
    end

    def format_timestamp(seconds)
      total = seconds.to_f.floor
      hours = total / 3600
      minutes = (total % 3600) / 60
      secs = total % 60
      format("%02d:%02d:%02d", hours, minutes, secs)
    end

    def print_success(action)
      puts "OK (#{action}): #{slug}"
      puts "  raw:  #{raw_json_path}"
      puts "  json: #{final_json_path}"
      puts "  md:   #{markdown_path}"
      puts "  map:  #{speaker_map_path}"
    end
  end
end
