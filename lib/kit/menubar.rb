# frozen_string_literal: true

require "open3"
require "rbconfig"

module Kit
  module MenuBar
    ROOT = File.expand_path("../..", __dir__)
    PACKAGE_DIR = File.join(ROOT, "mac", "menubar")
    EXECUTABLE_NAME = "KitMenuBar"
    KIT_CLI = File.join(ROOT, "bin", "kit")

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

    class Launcher
      def initialize(
        package_dir: PACKAGE_DIR,
        kit_cli: ENV.fetch("KIT_CLI", KIT_CLI),
        swift: "swift",
        spawner: nil,
        which: nil,
        dry_run: ENV.fetch("KIT_MENUBAR_DRY_RUN", "") == "1"
      )
        @package_dir = File.expand_path(package_dir)
        @kit_cli = File.expand_path(kit_cli)
        @swift = swift
        @spawner = spawner || method(:default_spawn)
        @which = which || method(:default_which)
        @dry_run = dry_run
      end

      def start(foreground: false)
        validate!

        command = [@swift, "run", EXECUTABLE_NAME]
        return dry_run_result(command, foreground) if @dry_run

        env = ENV.to_h.merge("KIT_CLI" => @kit_cli)
        pid = @spawner.call(env, command, @package_dir, foreground)
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
    end

    def self.start(foreground: false, launcher: Launcher.new)
      launcher.start(foreground: foreground)
    end
  end
end
