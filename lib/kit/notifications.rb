# frozen_string_literal: true

require "open3"

module Kit
  module Notifications
    class ValidationError < Error; end

    DeliveryResult = Struct.new(
      :success?,
      :notification,
      :backend,
      :command,
      :stdout,
      :stderr,
      :status,
      :error,
      :dry_run,
      keyword_init: true
    )

    class Notification
      attr_reader :title, :message, :subtitle, :sound, :group, :open

      def initialize(title:, message: nil, body: nil, subtitle: nil, sound: nil, group: nil, open: nil)
        @title = required_string(title, "title")
        @message = required_string(message || body, "message")
        @subtitle = optional_string(subtitle)
        @sound = optional_string(sound)
        @group = optional_string(group)
        @open = optional_string(open)
      end

      private

      def required_string(value, label)
        string = value.to_s.strip
        raise ValidationError, "notification #{label} is required" if string.empty?

        string
      end

      def optional_string(value)
        string = value.to_s.strip
        string.empty? ? nil : string
      end
    end

    class TerminalNotifierBackend
      attr_reader :executable

      def initialize(executable: "terminal-notifier", runner: nil)
        @executable = executable
        @runner = runner || ->(argv) { Open3.capture3(*argv) }
      end

      def deliver(notification)
        command = command_for(notification)
        stdout, stderr, status = @runner.call(command)

        DeliveryResult.new(
          success?: status.success?,
          notification: notification,
          backend: self,
          command: command,
          stdout: stdout,
          stderr: stderr,
          status: status,
          error: status.success? ? nil : stderr.to_s.strip,
          dry_run: false
        )
      rescue Errno::ENOENT
        DeliveryResult.new(
          success?: false,
          notification: notification,
          backend: self,
          command: command || command_for(notification),
          error: "#{@executable} is not installed or not on PATH",
          dry_run: false
        )
      end

      def command_for(notification)
        command = [
          @executable,
          "-title", notification.title,
          "-message", notification.message
        ]
        command.push("-subtitle", notification.subtitle) if notification.subtitle
        command.push("-sound", notification.sound) if notification.sound
        command.push("-group", notification.group) if notification.group
        command.push("-open", notification.open) if notification.open
        command
      end
    end

    class NullBackend
      def deliver(notification)
        command = TerminalNotifierBackend.new.command_for(notification)

        DeliveryResult.new(
          success?: true,
          notification: notification,
          backend: self,
          command: command,
          stdout: "",
          stderr: "",
          error: nil,
          dry_run: true
        )
      end
    end

    def self.deliver(title:, message: nil, body: nil, subtitle: nil, sound: nil, group: nil, open: nil, backend: TerminalNotifierBackend.new)
      notification = Notification.new(
        title: title,
        message: message,
        body: body,
        subtitle: subtitle,
        sound: sound,
        group: group,
        open: open
      )
      backend.deliver(notification)
    end
  end
end
