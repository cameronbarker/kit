# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"

module Kit::Listen
  class Pipeline
    attr_reader :input_path, :transcripts_dir, :mock

    def initialize(input:, transcripts_dir: DEFAULT_TRANSCRIPTS_DIR, mock: false)
      @input_path = File.expand_path(input)
      @transcripts_dir = File.expand_path(transcripts_dir)
      @mock = mock
    end

    def transcribe
      validate_input!
      ensure_directories!
      run_python_worker!
      finalize_from_raw!
      print_success("transcribe")
      0
    end

    def render
      validate_input!
      ensure_directories!
      raise Error, "raw JSON not found: #{raw_json_path}" unless File.file?(raw_json_path)

      finalize_from_raw!
      print_success("render")
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
      python = ENV.fetch("PYTHON", "python3")
      args = [python, PYTHON_WORKER, "--input", input_path, "--output", raw_json_path]
      args << "--mock" if mock

      stdout, stderr, status = Open3.capture3(*args)
      warn stderr unless stderr.to_s.strip.empty?
      unless status.success?
        detail = [stdout, stderr].map { |s| s.to_s.strip }.reject(&:empty?).join("\n")
        raise Error, "Python worker failed (exit #{status.exitstatus}).#{detail.empty? ? '' : "\n#{detail}"}"
      end
      raise Error, "Python worker did not create raw JSON: #{raw_json_path}" unless File.file?(raw_json_path)
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

        return map.transform_keys(&:to_s).transform_values(&:to_s)
      end

      labels = segments.map { |s| s["speaker"].to_s }.reject(&:empty?).uniq.sort
      map = labels.to_h { |label| [label, label] }
      File.write(speaker_map_path, YAML.dump(map))
      map
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
