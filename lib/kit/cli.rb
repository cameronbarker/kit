# frozen_string_literal: true

module Kit
  class CLI
    PLANNED_COMMANDS = {
      "listen" => "Record and transcribe conversations",
      "notice" => "Extract commitments, decisions, risks, and open loops",
      "remember" => "Write reviewed items into Obsidian/PARA",
      "surface" => "Show what needs attention now",
      "prepare" => "Build context packs for meetings and 1:1s",
      "brief" => "Draft leadership and stakeholder updates",
      "followup" => "Track promises, waiting-on items, and stale loops",
      "reflect" => "Review patterns over time",
      "qmd" => "Manage/search the local qmd index"
    }.freeze

    IMPLEMENTED_COMMANDS = {
      "notify" => "Send a simple local Kit notification"
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

    def notify_dry_run?
      ENV.fetch("KIT_NOTIFY_DRY_RUN", "") == "1"
    end
  end
end
