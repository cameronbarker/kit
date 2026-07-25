# frozen_string_literal: true

require "rbconfig"
require "time"

module Kit
  module AppBridge
    class Status
      DEFAULT_COMMANDS = {
        "open_loops" => {
          "label" => "Today's open loops",
          "command" => ["kit", "surface", "--json"],
          "implemented" => false
        },
        "overdue_commitments" => {
          "label" => "Overdue commitments",
          "command" => ["kit", "followup", "--overdue", "--json"],
          "implemented" => false
        },
        "today_surface" => {
          "label" => "Open today's surface",
          "command" => ["kit", "surface"],
          "implemented" => false
        },
        "listen" => {
          "label" => "Start listening",
          "command" => ["kit", "listen", "start"],
          "implemented" => true
        },
        "listen_pause" => {
          "label" => "Pause listening",
          "command" => ["kit", "listen", "pause", "--json"],
          "implemented" => true
        },
        "listen_resume" => {
          "label" => "Resume listening",
          "command" => ["kit", "listen", "resume", "--json"],
          "implemented" => true
        },
        "listen_stop" => {
          "label" => "Stop listening",
          "command" => ["kit", "listen", "stop", "--json"],
          "implemented" => true
        },
        "next_meeting_prep" => {
          "label" => "Open next meeting prep",
          "command" => ["kit", "prepare", "--next", "--json"],
          "implemented" => false
        },
        "brief" => {
          "label" => "Run brief",
          "command" => ["kit", "brief", "--json"],
          "implemented" => false
        },
        "quick_capture" => {
          "label" => "Quick capture",
          "command" => ["kit", "notice", "--capture", "--json"],
          "implemented" => false
        }
      }.freeze

      def initialize(now: Time.now, executable: $PROGRAM_NAME, ruby: RbConfig.ruby, notification_executable: "terminal-notifier")
        @now = now
        @executable = executable
        @ruby = ruby
        @notification_executable = notification_executable
      end

      def to_h
        {
          "schema_version" => 1,
          "kit_version" => VERSION,
          "generated_at" => @now.utc.iso8601,
          "health" => health,
          "commands" => DEFAULT_COMMANDS,
          "integration" => integration,
          "notifications" => notifications
        }
      end

      private

      def health
        {
          "indicator" => "setup",
          "message" => "Kit menu bar bridge is available; most attention commands are planned."
        }
      end

      def integration
        {
          "mode" => "cli_json",
          "kit_command" => [@ruby, @executable],
          "stable_entrypoints" => [
            ["kit", "status", "--json"],
            ["kit", "listen", "status", "--json"],
            ["kit", "notice", "--json"],
            ["kit", "remember", "--json"],
            ["kit", "surface", "--json"],
            ["kit", "prepare", "--next", "--json"],
            ["kit", "brief", "--json"]
          ]
        }
      end

      def notifications
        {
          "backend" => "terminal-notifier",
          "app_icon" => Notifications::DEFAULT_APP_ICON,
          "available" => executable_available?(@notification_executable)
        }
      end

      def executable_available?(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, name)
          File.file?(path) && File.executable?(path)
        end
      end
    end
  end
end
