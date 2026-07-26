# frozen_string_literal: true

require "json"

module Kit
  class CLI
    PLANNED_COMMANDS = {}.freeze

    IMPLEMENTED_COMMANDS = {
      "listen" => "Record and transcribe conversations",
      "notice" => "Extract commitments, decisions, and open loops",
      "remember" => "Write notice items into durable notes",
      "surface" => "Show what needs attention now",
      "prepare" => "Build context packs for meetings and 1:1s",
      "followup" => "Track promises, waiting-on items, and stale loops",
      "brief" => "Draft leadership and stakeholder updates",
      "reflect" => "Review patterns over time",
      "qmd" => "Manage/search the local qmd index",
      "notify" => "Send a simple local Kit notification",
      "status" => "Show machine-readable Kit app bridge status",
      "menubar" => "Start the macOS Kit menu bar helper"
    }.freeze

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
    end

    def run
      command = @argv.shift

      case command
      when nil, "help", "-h", "--help"
        print_help
        0
      when "version", "-v", "--version"
        @out.puts "kit #{VERSION}"
        0
      when "notify"
        run_notify
      when "status"
        run_status
      when "menubar"
        run_menubar
      when "listen"
        Listen::CLI.run(@argv)
      when "notice"
        Notice::CLI.run(@argv)
      when "remember"
        Remember::CLI.run(@argv)
      when "surface"
        Surface::CLI.run(@argv)
      when "prepare"
        Prepare::CLI.run(@argv)
      when "followup"
        Followup::CLI.run(@argv)
      when "brief"
        Brief::CLI.run(@argv)
      when "reflect"
        Reflect::CLI.run(@argv)
      when "qmd"
        Qmd::CLI.run(@argv)
      when *PLANNED_COMMANDS.keys
        print_planned(command)
        2
      else
        @err.puts "Unknown command: #{command}"
        @err.puts
        print_commands(@err)
        1
      end
    end

    private

    def print_help
      @out.puts <<~HELP
        kit #{VERSION}

        Personal leadership toolkit for engineering managers.

        Workflow:
          listen -> notice -> remember -> surface -> prepare/brief/followup -> reflect

        Commands:
      HELP
      print_commands(@out)
      @out.puts <<~HELP

        Meta:
          help        Show this help
          version     Show version

        Note:
          These commands define the intended system surface. Most are planned and not implemented yet.
      HELP
    end

    def print_commands(io)
      IMPLEMENTED_COMMANDS.each do |name, description|
        io.puts "  #{name.ljust(11)} #{description}"
      end
      PLANNED_COMMANDS.each do |name, description|
        io.puts "  #{name.ljust(11)} #{description}"
      end
    end

    def print_planned(command)
      @err.puts "kit #{command} is planned but not implemented yet."
      @err.puts PLANNED_COMMANDS.fetch(command)
      @err.puts "Run `kit help` to see the full command surface."
    end

    def run_notify
      message = @argv.join(" ").strip
      raise Error, "missing MESSAGE" if message.empty?

      backend = notify_dry_run? ? Notifications::NullBackend.new : Notifications::TerminalNotifierBackend.new
      result = Notifications.deliver(title: "Kit", message: message, backend: backend)
      @out.puts result.command.join(" ") if result.dry_run
      return 0 if result.success?

      @err.puts "Error: #{result.error}"
      1
    rescue Error => e
      @err.puts "Error: #{e.message}"
      1
    end

    def run_status
      json = false
      case @argv
      when []
        json = false
      when ["--json"]
        json = true
      else
        raise Error, "usage: kit status [--json]"
      end

      payload = AppBridge::Status.new.to_h
      if json
        @out.puts JSON.pretty_generate(payload)
      else
        @out.puts "kit=#{payload['kit_version']} health=#{payload.dig('health', 'indicator')}"
      end
      0
    rescue Error => e
      @err.puts "Error: #{e.message}"
      1
    end

    def run_menubar
      foreground = false
      @argv.each do |arg|
        case arg
        when "start", "help", "-h", "--help"
          next if arg == "start"

          print_menubar_help
          return 0
        when "--foreground"
          foreground = true
        else
          raise Error, "usage: kit menubar [start] [--foreground]"
        end
      end

      result = MenuBar.start(foreground: foreground)
      unless result.success?
        @err.puts "Error: #{result.error}"
        return 1
      end

      if result.dry_run
        @out.puts result.command.join(" ")
        return 0
      end

      if foreground
        @out.puts "Starting Kit menu bar in the foreground (pid #{result.pid})..."
        _pid, status = Process.wait2(result.pid)
        return status.exitstatus
      end

      @out.puts "Started Kit menu bar (pid #{result.pid})"
      0
    rescue Error => e
      @err.puts "Error: #{e.message}"
      1
    end

    def print_menubar_help
      @out.puts <<~HELP
        Usage: kit menubar [start] [--foreground]

        Start the thin macOS Kit menu bar helper from mac/menubar.

        Options:
          --foreground    Keep the CLI attached to the menu bar process
      HELP
    end

    def notify_dry_run?
      ENV.fetch("KIT_NOTIFY_DRY_RUN", "") == "1"
    end
  end
end
