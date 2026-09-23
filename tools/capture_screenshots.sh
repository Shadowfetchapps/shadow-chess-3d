#!/usr/bin/env bash
# Renders the documentation screenshots from the running game.
# Uses a throwaway XDG config/data dir so real saves and settings are untouched.
#   ./tools/capture_screenshots.sh [output-dir] [quality]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
OUT="${1:-$ROOT/docs/screenshots}"
QUALITY="${2:-high}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data" \
	"$GODOT" --path "$ROOT" --resolution 1600x900 -- --visual-qa "--shots=$OUT" "--quality=$QUALITY"
