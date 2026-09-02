#!/usr/bin/env bash
# UI playtests. Fails on a non-zero Godot exit or SCRIPT ERROR in the log.
# Godot does not fail a test when a UI callback throws.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"
log="$root/build/playtests.log"
set +e
godot --headless --path "$root" res://tests/run_playtests.tscn 2>&1 | tee "$log"
exit_code=${PIPESTATUS[0]}
set -e
if [[ "$exit_code" == "" ]]; then
  exit_code=1
fi
if grep -F -q "SCRIPT ERROR" "$log"; then
  echo "Playtests: SCRIPT ERROR in $log"
  exit 1
fi
exit "$exit_code"
