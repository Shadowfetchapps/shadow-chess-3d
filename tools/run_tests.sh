#!/usr/bin/env bash
# Runs every headless suite. Exit status is non-zero if any suite fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
status=0
"$GODOT" --headless --path "$ROOT" --script res://tests/test_runner.gd || status=1
"$GODOT" --headless --path "$ROOT" res://tests/scene_runner.tscn || status=1
if [[ $status -eq 0 ]]; then
	echo "ALL SUITES PASSED"
else
	echo "SOME SUITES FAILED" >&2
fi
exit $status
