#!/usr/bin/env bash
# Headless correctness suite. Exit code is the number of failed assertions.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
godot --headless --path "$root" res://tests/run_tests.tscn
