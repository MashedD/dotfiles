#!/usr/bin/env bash

set -euo pipefail

stow_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly stow_dir
target_dir="${HOME:?HOME must be set}"
readonly target_dir
package_name='dotfiles'
readonly package_name

usage() {
  cat <<'EOF'
Usage: ./stow.sh [check|apply|unlink|help]

  check   Simulate applying the dotfiles package and report conflicts (default).
  apply   Apply the package only after a successful simulated preflight.
  unlink  Remove only links owned by this package after a simulated preflight.
  help    Show this message.

Conflicts are never overwritten, backed up, or adopted automatically. Resolve
them manually, then run `./stow.sh check` again before applying changes.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 127
  fi
}

simulate() {
  stow --simulate --verbose=1 --dir "$stow_dir" --target "$target_dir" "$@" "$package_name"
}

run_stow() {
  stow --dir "$stow_dir" --target "$target_dir" "$@" "$package_name"
}

check() {
  require_command stow

  if simulate --restow; then
    printf 'Preflight passed: %s can be applied to %s.\n' "$package_name" "$target_dir"
  else
    printf '%s\n' 'Preflight failed; resolve the reported conflicts manually. No files were changed.' >&2
    return 1
  fi
}

refresh_fonts() {
  fc-cache -f
}

apply() {
  require_command stow
  require_command fc-cache
  check
  run_stow --restow
  refresh_fonts
}

unlink() {
  require_command stow
  require_command fc-cache

  if ! simulate --delete; then
    printf '%s\n' 'Unlink preflight failed; no files were changed.' >&2
    return 1
  fi

  run_stow --delete
  refresh_fonts
}

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 64
fi

case "${1:-check}" in
  check)
    check
    ;;
  apply)
    apply
    ;;
  unlink)
    unlink
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
