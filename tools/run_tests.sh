#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
exec "$GODOT" --headless --path "$ROOT" --script res://tests/test_runner.gd
