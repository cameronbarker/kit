# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/kit"

class KitEnvTest < Minitest::Test
  def test_load_sets_missing_keys_from_dotenv_file
    Dir.mktmpdir("kit-env-") do |dir|
      path = File.join(dir, ".env")
      File.write(path, <<~ENV)
        # comment
        KIT_LISTEN_AUDIO_DEVICE=Base
        EMPTY_SKIP=
        QUOTED="Meet + Mic"
      ENV

      env = {}
      assert_equal true, Kit::Env.load!(path: path, into: env)
      assert_equal "Base", env["KIT_LISTEN_AUDIO_DEVICE"]
      assert_equal "", env["EMPTY_SKIP"]
      assert_equal "Meet + Mic", env["QUOTED"]
    end
  end

  def test_load_does_not_override_existing_env
    Dir.mktmpdir("kit-env-") do |dir|
      path = File.join(dir, ".env")
      File.write(path, "KIT_LISTEN_AUDIO_DEVICE=Base\n")

      env = { "KIT_LISTEN_AUDIO_DEVICE" => "FromShell" }
      Kit::Env.load!(path: path, into: env)
      assert_equal "FromShell", env["KIT_LISTEN_AUDIO_DEVICE"]
    end
  end

  def test_load_returns_false_when_missing
    assert_equal false, Kit::Env.load!(path: "/tmp/kit-missing-env-#{Process.pid}", into: {})
  end
end
