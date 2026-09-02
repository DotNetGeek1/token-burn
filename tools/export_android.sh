#!/usr/bin/env bash
# Merge the committed Android preset into export_presets.cfg (without
# clobbering Web) and export an AAB. Signing uses Godot's
# GODOT_ANDROID_KEYSTORE_* environment variables; nothing is written to git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/build/android"
AAB="$OUT_DIR/token_burn.aab"

if ! command -v godot >/dev/null 2>&1; then
  echo "godot not found on PATH."
  exit 1
fi
if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "python not found on PATH."
  exit 1
fi

"$PYTHON" "$ROOT/tools/merge_android_preset.py"

mkdir -p "$OUT_DIR"
MODE="debug"
EXPORT_FLAG="--export-debug"
if [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]]; then
  MODE="release"
  EXPORT_FLAG="--export-release"
fi

echo "Exporting Android $MODE AAB to $AAB"
rm -f "$AAB"
STAMP="$(mktemp)"
set +e
godot --headless --path "$ROOT" --install-android-build-template "$EXPORT_FLAG" Android "$AAB"
GODOT_EXIT=$?
set -e

# Editor addons can make Godot exit non-zero after a successful export
# (teardown errors). A freshly written AAB is the real signal.
if [[ ! -f "$AAB" || ! "$AAB" -nt "$STAMP" ]]; then
  rm -f "$STAMP"
  echo "Godot export failed (exit $GODOT_EXIT) and no new $AAB was written."
  if [[ "$GODOT_EXIT" -ne 0 ]]; then exit "$GODOT_EXIT"; fi
  exit 1
fi
rm -f "$STAMP"
if [[ "$GODOT_EXIT" -ne 0 ]]; then
  echo "Godot exited $GODOT_EXIT after writing the AAB; continuing (editor addon teardown noise)."
fi

INSPECT=("$PYTHON" "$ROOT/tools/inspect_aab.py" "$AAB")
if [[ -n "${BUNDLETOOL_JAR:-}" ]]; then
  INSPECT+=(--bundletool "$BUNDLETOOL_JAR")
fi
"${INSPECT[@]}"
