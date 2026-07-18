# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "../../../lib/kit"

class Kit::ListenPipelineTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("leadership-transcripts-test-")
    @input = File.join(@tmpdir, "platform_sync.m4a")
    File.write(@input, "fake-audio")
    @transcripts_dir = File.join(@tmpdir, "transcripts")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def pipeline(input: @input, mock: true)
    Kit::Listen::Pipeline.new(
      input: input,
      transcripts_dir: @transcripts_dir,
      mock: mock
    )
  end

  def test_missing_input_raises
    missing = pipeline(input: File.join(@tmpdir, "missing.m4a"))

    error = assert_raises(Kit::Listen::Error) { missing.transcribe }
    assert_match(/input file not found/, error.message)
  end

  def test_mock_transcribe_creates_artifacts_and_speaker_map
    status = pipeline.transcribe

    assert_equal 0, status

    slug = "platform-sync"
    raw_path = File.join(@transcripts_dir, "raw", "#{slug}.raw.json")
    json_path = File.join(@transcripts_dir, "json", "#{slug}.json")
    md_path = File.join(@transcripts_dir, "md", "#{slug}.md")
    map_path = File.join(@transcripts_dir, "maps", "#{slug}.speaker-map.yml")

    assert File.file?(raw_path)
    assert File.file?(json_path)
    assert File.file?(md_path)
    assert File.file?(map_path)

    raw = JSON.parse(File.read(raw_path))
    assert_equal true, raw["mock"]
    assert_equal 2, raw["segments"].length

    map = YAML.safe_load(File.read(map_path))
    assert_equal "SPEAKER_00", map["SPEAKER_00"]
    assert_equal "SPEAKER_01", map["SPEAKER_01"]

    final = JSON.parse(File.read(json_path))
    assert_equal "Platform Sync", final["title"]
    assert_equal @input, final["source_file"]
    assert final["generated_at"]
    assert_equal "SPEAKER_00", final["segments"][0]["speaker"]
    assert_equal "SPEAKER_00", final["segments"][0]["raw_speaker"]
    assert_in_delta 72.0, final["segments"][0]["start"], 0.001

    markdown = File.read(md_path)
    assert_includes markdown, "# Platform Sync"
    assert_includes markdown, "Source: #{@input}"
    assert_includes markdown, "[00:01:12] SPEAKER_00:"
    assert_includes markdown, "[00:01:18] SPEAKER_01:"
  end

  def test_existing_speaker_map_is_applied
    pipe = pipeline
    FileUtils.mkdir_p(File.dirname(pipe.speaker_map_path))
    File.write(
      pipe.speaker_map_path,
      YAML.dump(
        {
          "SPEAKER_00" => "Cameron",
          "SPEAKER_01" => "Rachel"
        }
      )
    )

    assert_equal 0, pipe.transcribe

    final = JSON.parse(File.read(pipe.final_json_path))
    assert_equal "Cameron", final["segments"][0]["speaker"]
    assert_equal "SPEAKER_00", final["segments"][0]["raw_speaker"]
    assert_equal "Rachel", final["segments"][1]["speaker"]
    assert_equal "SPEAKER_01", final["segments"][1]["raw_speaker"]

    markdown = File.read(pipe.markdown_path)
    assert_includes markdown, "[00:01:12] Cameron:"
    assert_includes markdown, "[00:01:18] Rachel:"
  end

  def test_render_rebuilds_from_raw_without_python
    pipe = pipeline
    assert_equal 0, pipe.transcribe

    File.write(
      pipe.speaker_map_path,
      YAML.dump(
        {
          "SPEAKER_00" => "Cameron",
          "SPEAKER_01" => "Rachel"
        }
      )
    )

    # Break final artifacts, then rebuild via render only.
    File.write(pipe.final_json_path, "{}\n")
    File.write(pipe.markdown_path, "# stale\n")

    # Guard: render must not require Python worker success beyond existing raw JSON.
    assert_equal 0, pipeline(mock: false).render

    final = JSON.parse(File.read(pipe.final_json_path))
    assert_equal "Cameron", final["segments"][0]["speaker"]
    assert_equal "SPEAKER_00", final["segments"][0]["raw_speaker"]

    markdown = File.read(pipe.markdown_path)
    assert_includes markdown, "[00:01:12] Cameron:"
    refute_includes markdown, "# stale"
  end
end
