#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./install.sh [install|--doctor|--help]

Commands:
  install     Install missing Kit runtime dependencies (default)
  --doctor    Check whether runtime dependencies are available
  --help      Show this help

Currently installs/checks:
  terminal-notifier
USAGE
}

check_terminal_notifier() {
  command -v terminal-notifier >/dev/null 2>&1
}

doctor() {
  if check_terminal_notifier; then
    printf 'terminal-notifier: %s\n' "$(command -v terminal-notifier)"
    return 0
  fi

  printf 'terminal-notifier: missing\n' >&2
  return 1
}

install_terminal_notifier() {
  if check_terminal_notifier; then
    printf 'terminal-notifier already installed: %s\n' "$(command -v terminal-notifier)"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    printf 'Error: Homebrew is required to install terminal-notifier.\n' >&2
    printf 'Install Homebrew first, then rerun ./install.sh.\n' >&2
    return 1
  fi

  brew install terminal-notifier
}

command_name="${1:-install}"

case "$command_name" in
  install)
    install_terminal_notifier
    ;;
  --doctor)
    doctor
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$command_name" >&2
    usage >&2
    exit 2
    ;;
esac
