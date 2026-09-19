#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
OUT="$ROOT/export/linux/shadow-chess-3d.x86_64"
mkdir -p "$ROOT/export/linux"
exec "$GODOT" --headless --path "$ROOT" --export-release Linux "$OUT"
