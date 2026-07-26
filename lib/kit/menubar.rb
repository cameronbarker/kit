# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

module Kit
  module MenuBar
    ROOT = File.expand_path("../..", __dir__)
    PACKAGE_DIR = File.join(ROOT, "mac", "menubar")
    EXECUTABLE_NAME = "KitMenuBar"
    KIT_CLI = File.join(ROOT, "bin", "kit")
    ICON_PATH = File.join(ROOT, "assets", "Kit-Logo-2424r.png")
    PID_FILE = ENV.fetch("KIT_MENUBAR_PID_FILE", File.join(Dir.tmpdir, "kit-menubar.pid"))

    LaunchResult = Struct.new(
      :success?,
      :pid,
      :command,
      :package_dir,
      :kit_cli,
      :foreground,
      :dry_run,
      :error,
      keyword_init: true
    )

    StopResult = Struct.new(
      :success?,
      :pid,
      :pid_file,
      :stopped,
      :error,
      keyword_init: true
    )

    class Launcher
      def initialize(
        package_dir: PACKAGE_DIR,
        kit_cli: ENV.fetch("KIT_CLI", KIT_CLI),
        swift: "swift",
        spawner: nil,
        which: nil,
        pid_file: PID_FILE,
        dry_run: ENV.fetch("KIT_MENUBAR_DRY_RUN", "") == "1"
      )
        @package_dir = File.expand_path(package_dir)
        @kit_cli = File.expand_path(kit_cli)
        @swift = swift
        @spawner = spawner || method(:default_spawn)
        @which = which || method(:default_which)
        @pid_file = pid_file
        @dry_run = dry_run
      end

      def start(foreground: false)
        validate!

        command = [@swift, "run", EXECUTABLE_NAME]
        return dry_run_result(command, foreground) if @dry_run

        env = ENV.to_h.merge(
          "KIT_CLI" => @kit_cli,
          "KIT_MENUBAR_ICON" => ICON_PATH
        )
        pid = @spawner.call(env, command, @package_dir, foreground)
        write_pid(pid) unless foreground
        LaunchResult.new(
          success?: true,
          pid: pid,
          command: command,
          package_dir: @package_dir,
          kit_cli: @kit_cli,
          foreground: foreground,
          dry_run: false,
          error: nil
        )
      rescue Error => e
        LaunchResult.new(
          success?: false,
          pid: nil,
          command: [@swift, "run", EXECUTABLE_NAME],
          package_dir: @package_dir,
          kit_cli: @kit_cli,
          foreground: foreground,
          dry_run: @dry_run,
          error: e.message
        )
      end

      private

      def dry_run_result(command, foreground)
        LaunchResult.new(
          success?: true,
          pid: 0,
          command: command,
          package_dir: @package_dir,
          kit_cli: @kit_cli,
          foreground: foreground,
          dry_run: true,
          error: nil
        )
      end

      def validate!
        unless RbConfig::CONFIG["host_os"].to_s.include?("darwin")
          raise Error, "kit menubar requires macOS"
        end

        unless File.file?(File.join(@package_dir, "Package.swift"))
          raise Error, "menu bar package not found at #{@package_dir}"
        end

        unless File.file?(@kit_cli)
          raise Error, "kit CLI not found at #{@kit_cli}"
        end

        return if @dry_run

        unless @which.call(@swift)
          raise Error, "#{@swift} is not installed or not on PATH"
        end
      end

      def default_which(executable)
        stdout, _stderr, status = Open3.capture3("which", executable)
        status.success? && !stdout.strip.empty?
      rescue Errno::ENOENT
        false
      end

      def default_spawn(env, command, package_dir, foreground)
        if foreground
          Process.spawn(env, *command, chdir: package_dir)
        else
          pid = Process.spawn(
            env,
            *command,
            chdir: package_dir,
            out: File::NULL,
            err: File::NULL,
            pgroup: true
          )
          Process.detach(pid)
          pid
        end
      end

      def write_pid(pid)
        File.write(@pid_file, "#{pid}\n")
      end
    end

    class Stopper
      def initialize(
        pid_file: PID_FILE,
        killer: nil,
        process_exists: nil
      )
        @pid_file = pid_file
        @killer = killer || method(:default_kill)
        @process_exists = process_exists || method(:default_process_exists?)
      end

      def stop
        pid = read_pid
        return success(pid: nil, stopped: false) unless pid

        unless @process_exists.call(pid)
          remove_pid_file
          return success(pid: pid, stopped: false)
        end

        @killer.call(pid)
        remove_pid_file
        success(pid: pid, stopped: true)
      rescue Error => e
        StopResult.new(
          success?: false,
          pid: nil,
          pid_file: @pid_file,
          stopped: false,
          error: e.message
        )
      end

      private

      def read_pid
        return nil unless File.file?(@pid_file)

        raw = File.read(@pid_file).strip
        return Integer(raw, exception: false) if raw.match?(/\A\d+\z/)

        remove_pid_file
        raise Error, "invalid menu bar pid file at #{@pid_file}"
      end

      def remove_pid_file
        File.delete(@pid_file) if File.file?(@pid_file)
      end

      def default_process_exists?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def default_kill(pid)
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
        Process.kill("TERM", pid)
      end

      def success(pid:, stopped:)
        StopResult.new(
          success?: true,
          pid: pid,
          pid_file: @pid_file,
          stopped: stopped,
          error: nil
        )
      end
    end

    def self.start(foreground: false, launcher: Launcher.new)
      launcher.start(foreground: foreground)
    end

    def self.stop(stopper: Stopper.new)
      stopper.stop
    end
  end
end
