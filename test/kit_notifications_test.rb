# frozen_string_literal: true

require "minitest/autorun"

require_relative "../lib/kit"

class KitNotificationsTest < Minitest::Test
  FakeStatus = Struct.new(:success?)

  def test_notification_requires_title
    error = assert_raises(Kit::Notifications::ValidationError) do
      Kit::Notifications::Notification.new(title: " ", message: "Review")
    end

    assert_equal "notification title is required", error.message
  end

  def test_notification_requires_message
    error = assert_raises(Kit::Notifications::ValidationError) do
      Kit::Notifications::Notification.new(title: "Kit", message: nil)
    end

    assert_equal "notification message is required", error.message
  end

  def test_notification_accepts_body_alias
    notification = Kit::Notifications::Notification.new(title: "Kit", body: "Review")

    assert_equal "Review", notification.message
  end

  def test_terminal_notifier_command_for_required_fields
    notification = Kit::Notifications::Notification.new(title: "Kit", message: "Review open commitments")
    command = Kit::Notifications::TerminalNotifierBackend.new.command_for(notification)

    assert_equal ["terminal-notifier", "-title", "Kit", "-message", "Review open commitments"], command
  end

  def test_terminal_notifier_command_for_optional_fields
    notification = Kit::Notifications::Notification.new(
      title: "Kit",
      message: "Prep for 1:1",
      subtitle: "Meeting Prep",
      sound: "Glass",
      group: "kit-prepare",
      open: "obsidian://open?vault=Leadership"
    )
    command = Kit::Notifications::TerminalNotifierBackend.new.command_for(notification)

    assert_equal [
      "terminal-notifier",
      "-title", "Kit",
      "-message", "Prep for 1:1",
      "-subtitle", "Meeting Prep",
      "-sound", "Glass",
      "-group", "kit-prepare",
      "-open", "obsidian://open?vault=Leadership"
    ], command
  end

  def test_command_uses_argv_values_without_shell_escaping
    notification = Kit::Notifications::Notification.new(
      title: 'Kit "Daily"',
      message: "Line 1\nLine 2 \\ done"
    )
    command = Kit::Notifications::TerminalNotifierBackend.new.command_for(notification)

    assert_equal 'Kit "Daily"', command[2]
    assert_equal "Line 1\nLine 2 \\ done", command[4]
  end

  def test_terminal_notifier_backend_delivers_with_runner
    calls = []
    runner = lambda do |argv|
      calls << argv
      ["", "", FakeStatus.new(true)]
    end
    backend = Kit::Notifications::TerminalNotifierBackend.new(runner: runner)
    notification = Kit::Notifications::Notification.new(title: "Kit", message: "Review")

    result = backend.deliver(notification)

    assert result.success?
    refute result.dry_run
    assert_equal [["terminal-notifier", "-title", "Kit", "-message", "Review"]], calls
  end

  def test_terminal_notifier_backend_returns_failure_for_missing_executable
    runner = ->(_argv) { raise Errno::ENOENT }
    backend = Kit::Notifications::TerminalNotifierBackend.new(runner: runner)
    notification = Kit::Notifications::Notification.new(title: "Kit", message: "Review")

    result = backend.deliver(notification)

    refute result.success?
    assert_equal "terminal-notifier is not installed or not on PATH", result.error
    assert_equal ["terminal-notifier", "-title", "Kit", "-message", "Review"], result.command
  end

  def test_null_backend_does_not_execute
    notification = Kit::Notifications::Notification.new(title: "Kit", message: "Review")

    result = Kit::Notifications::NullBackend.new.deliver(notification)

    assert result.success?
    assert result.dry_run
    assert_equal ["terminal-notifier", "-title", "Kit", "-message", "Review"], result.command
  end

  def test_module_deliver_uses_supplied_backend
    backend = Kit::Notifications::NullBackend.new

    result = Kit::Notifications.deliver(title: "Kit", message: "Review", backend: backend)

    assert result.success?
    assert_equal backend, result.backend
  end
end
