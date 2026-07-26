# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/kit"

class KitMenuBarTest < Minitest::Test
  def test_launcher_starts_detached_swift_process
    spawned = nil
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      launcher = Kit::MenuBar::Launcher.new(
        package_dir: Kit::MenuBar::PACKAGE_DIR,
        kit_cli: Kit::MenuBar::KIT_CLI,
        pid_file: pid_file,
        which: ->(_exe) { true },
        spawner: lambda { |env, command, package_dir, foreground|
          spawned = {
            env: env,
            command: command,
            package_dir: package_dir,
            foreground: foreground
          }
          42_424
        }
      )

      result = launcher.start

      assert result.success?
      assert_equal 42_424, result.pid
      assert_equal false, result.foreground
      assert_equal false, result.dry_run
      assert_equal ["swift", "run", "KitMenuBar"], result.command
      assert_equal Kit::MenuBar::PACKAGE_DIR, spawned[:package_dir]
      assert_equal Kit::MenuBar::KIT_CLI, spawned[:env]["KIT_CLI"]
      assert_equal Kit::MenuBar::ICON_PATH, spawned[:env]["KIT_MENUBAR_ICON"]
      assert_equal false, spawned[:foreground]
      assert_equal "42424", File.read(pid_file).strip
      # Launcher forwards the process env (including .env-loaded values) to Swift.
      if ENV["KIT_LISTEN_AUDIO_DEVICE"]
        assert_equal ENV["KIT_LISTEN_AUDIO_DEVICE"], spawned[:env]["KIT_LISTEN_AUDIO_DEVICE"]
      end
    end
  end

  def test_launcher_can_start_in_foreground
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      launcher = Kit::MenuBar::Launcher.new(
        package_dir: Kit::MenuBar::PACKAGE_DIR,
        kit_cli: Kit::MenuBar::KIT_CLI,
        pid_file: pid_file,
        which: ->(_exe) { true },
        spawner: lambda { |_env, _command, _package_dir, foreground|
          assert foreground
          99
        }
      )

      result = launcher.start(foreground: true)

      assert result.success?
      assert_equal 99, result.pid
      assert result.foreground
      refute File.exist?(pid_file)
    end
  end

  def test_stopper_terminates_pid_from_file
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      File.write(pid_file, "42424\n")
      killed = nil
      stopper = Kit::MenuBar::Stopper.new(
        pid_file: pid_file,
        process_exists: ->(pid) { pid == 42_424 },
        killer: ->(pid) { killed = pid }
      )

      result = stopper.stop

      assert result.success?
      assert result.stopped
      assert_equal 42_424, result.pid
      assert_equal 42_424, killed
      refute File.exist?(pid_file)
    end
  end

  def test_stopper_reports_not_running_without_pid_file
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      stopper = Kit::MenuBar::Stopper.new(pid_file: pid_file)

      result = stopper.stop

      assert result.success?
      refute result.stopped
      assert_nil result.pid
    end
  end

  def test_stopper_removes_stale_pid_file
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      File.write(pid_file, "42424\n")
      stopper = Kit::MenuBar::Stopper.new(
        pid_file: pid_file,
        process_exists: ->(_pid) { false }
      )

      result = stopper.stop

      assert result.success?
      refute result.stopped
      assert_equal 42_424, result.pid
      refute File.exist?(pid_file)
    end
  end

  def test_stopper_rejects_invalid_pid_file
    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "kit-menubar.pid")
      File.write(pid_file, "nope\n")
      stopper = Kit::MenuBar::Stopper.new(pid_file: pid_file)

      result = stopper.stop

      refute result.success?
      assert_includes result.error, "invalid menu bar pid file"
      refute File.exist?(pid_file)
    end
  end

  def test_launcher_dry_run_skips_spawn
    called = false
    launcher = Kit::MenuBar::Launcher.new(
      package_dir: Kit::MenuBar::PACKAGE_DIR,
      kit_cli: Kit::MenuBar::KIT_CLI,
      dry_run: true,
      spawner: lambda { |*_args|
        called = true
        1
      }
    )

    result = launcher.start

    assert result.success?
    assert result.dry_run
    assert_equal 0, result.pid
    assert_equal ["swift", "run", "KitMenuBar"], result.command
    refute called
  end

  def test_launcher_requires_package
    launcher = Kit::MenuBar::Launcher.new(
      package_dir: File.join(Kit::MenuBar::ROOT, "mac", "missing-menubar"),
      kit_cli: Kit::MenuBar::KIT_CLI,
      dry_run: true
    )

    result = launcher.start

    refute result.success?
    assert_includes result.error, "menu bar package not found"
  end

  def test_launcher_requires_swift_when_not_dry_run
    launcher = Kit::MenuBar::Launcher.new(
      package_dir: Kit::MenuBar::PACKAGE_DIR,
      kit_cli: Kit::MenuBar::KIT_CLI,
      which: ->(_exe) { false }
    )

    result = launcher.start

    refute result.success?
    assert_equal "swift is not installed or not on PATH", result.error
  end
end
