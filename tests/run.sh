#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
usage() {
  printf 'Usage: %s [--session|--visual] [--scenario all|titlebars|workspace-transfer|sidebar-documents|sidebar-settings|menu-popups]\n' "$0"
  printf 'No mode: fast checks. --session: private runtime. --visual: runtime and XRender visual checks.\n'
  printf '%s\n' '--scenario selects runtime checks (default: all); it requires --session or --visual.'
}
invalid() { usage >&2; exit 64; }
mode='' scenario=''
while (( $# )); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --session|--visual) [[ -z "$mode" ]] || invalid; mode=$1 ;;
    --scenario|--scenario=*)
      [[ -z "$scenario" ]] || invalid
      if [[ "$1" == --scenario ]]; then
        (( $# >= 2 )) || invalid
        scenario=$2; shift
      else scenario=${1#*=}; fi
      case "$scenario" in all|titlebars|workspace-transfer|sidebar-documents|sidebar-settings|menu-popups) ;; *) invalid ;; esac ;;
    *) invalid ;;
  esac
  shift
done
[[ -z "$scenario" || -n "$mode" ]] || invalid
session_args=()
if [[ -n "$scenario" ]]; then session_args=(--scenario "$scenario"); fi
run() {
  printf '\n+ '; printf '%q ' "$@"; printf '\n'
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2; return 127
  fi
  "$@"
}
run bash -n stow.sh tests/run.sh
run awesome -k -c dotfiles/.config/awesome/rc.lua
for test in tests/test-awesome-*.lua; do run lua "$test"; done
for test in tests/test-awesome-autostart.py tests/test-awesome-controls.py tests/test-awesome-session-runner.py tests/test-awesome-lock.py tests/test-desktop-display.py tests/test-desktop-check.py tests/test-screen-lock.py tests/test-deployment.py tests/test-status-helpers.py tests/test-desktop-screenshot.py tests/test-updaterepo.py tests/test-idle-audit.py tests/test-control-center.py tests/test-dunst-theme.py; do
  run python3 "$test"
done
run_focused_session_checks() {
  if [[ -z "$scenario" || "$scenario" == all ]]; then
    run python3 tests/test-awesome-session.py --scenario workspace-transfer
    run python3 tests/test-awesome-session.py --scenario sidebar-documents
    run python3 tests/test-awesome-session.py --scenario sidebar-settings
  fi
}
case "$mode" in
  --session)
    run_focused_session_checks
    run python3 tests/test-awesome-session.py "${session_args[@]}" ;;
  --visual)
    run_focused_session_checks
    export AWESOME_TEST_VISUAL=1
    run python3 tests/test-awesome-session.py "${session_args[@]}"
    run python3 tests/test-awesome-session.py --composited "${session_args[@]}" ;;
esac
