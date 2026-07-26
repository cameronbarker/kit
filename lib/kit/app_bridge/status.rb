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
          "implemented" => true
        },
        "overdue_commitments" => {
          "label" => "Overdue commitments",
          "command" => ["kit", "followup", "--overdue", "--json"],
          "implemented" => true
        },
        "needs_review" => {
          "label" => "Needs review",
          "command" => ["kit", "surface", "--needs-review-only", "--json"],
          "implemented" => true
        },
        "waiting_on_me" => {
          "label" => "Waiting on me",
          "command" => ["kit", "followup", "--waiting-on-me", "--json"],
          "implemented" => true
        },
        "today_surface" => {
          "label" => "Today's Surface",
          "command" => ["kit", "surface"],
          "implemented" => true
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
          "label" => "Weekly Brief",
          "command" => ["kit", "brief", "--json"],
          "implemented" => true
        },
        "reflect" => {
          "label" => "Run reflection",
          "command" => ["kit", "reflect", "--json"],
          "implemented" => true
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
          "indicator" => "ok",
          "message" => "Ready: review, follow up, or capture."
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
            ["kit", "surface", "--needs-review-only", "--json"],
            ["kit", "followup", "--overdue", "--json"],
            ["kit", "followup", "--waiting-on-me", "--json"],
            ["kit", "prepare", "--next", "--json"],
            ["kit", "brief", "--json"],
            ["kit", "reflect", "--json"]
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
