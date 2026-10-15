#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
case "${1:-}" in
  ''|--session|--visual) ;;
  *) printf 'Usage: %s [--session|--visual]\n' "$0" >&2; exit 64 ;;
esac
if (( $# > 1 )); then printf 'Expected at most one option.\n' >&2; exit 64; fi
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
for test in tests/test-awesome-autostart.py tests/test-awesome-controls.py tests/test-awesome-lock.py tests/test-desktop-display.py tests/test-desktop-check.py tests/test-screen-lock.py tests/test-deployment.py; do
  run python3 "$test"
done
case "${1:-}" in
  --session) run python3 tests/test-awesome-session.py ;;
  --visual)
    export AWESOME_TEST_VISUAL=1
    run python3 tests/test-awesome-session.py
    run python3 tests/test-awesome-session.py --composited ;;
esac
