#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_SRC="$ROOT/export/linux/shadow-chess-3d.x86_64"
APP_ID="com.shadowfetch.Chess"
ICON_NAME="shadow-chess-3d"
BINDIR="${HOME}/.local/bin"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$BINDIR/shadow-chess-3d" "$BINDIR/shadow-chess-3d.pck"
  rm -f "$PREFIX/applications/${APP_ID}.desktop"
  rm -f "$PREFIX/applications/shadow-chess-3d.desktop"
  echo "Removed launcher and user-local binary. Saves in $PREFIX/shadow-chess-3d were kept."
  exit 0
fi

if [[ ! -x "$BIN_SRC" ]]; then
  echo "Exporting Linux release…"
  "$ROOT/tools/export_linux.sh"
fi

mkdir -p "$BINDIR" "$PREFIX/applications"
install -m 0755 "$BIN_SRC" "$BINDIR/shadow-chess-3d"
if [[ -f "$ROOT/export/linux/shadow-chess-3d.pck" ]]; then
  install -m 0644 "$ROOT/export/linux/shadow-chess-3d.pck" "$BINDIR/shadow-chess-3d.pck"
fi

if [[ -d "$ROOT/assets/icons/hicolor" ]]; then
  for size in 16 22 24 32 48 64 128 256 512; do
    src="$ROOT/assets/icons/hicolor/${size}x${size}/apps/${ICON_NAME}.png"
    if [[ -f "$src" ]]; then
      dest="$PREFIX/icons/hicolor/${size}x${size}/apps"
      mkdir -p "$dest"
      install -m 0644 "$src" "$dest/${ICON_NAME}.png"
    fi
  done
fi
if [[ -f "$ROOT/icon.svg" ]]; then
  mkdir -p "$PREFIX/icons/hicolor/scalable/apps"
  install -m 0644 "$ROOT/icon.svg" "$PREFIX/icons/hicolor/scalable/apps/${ICON_NAME}.svg"
fi

for desktop_name in "${APP_ID}.desktop" "shadow-chess-3d.desktop"; do
  cat > "$PREFIX/applications/${desktop_name}" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Shadow Chess 3D
GenericName=Chess
Comment=Premium 3D chess for Linux
Exec=${BINDIR}/shadow-chess-3d
TryExec=${BINDIR}/shadow-chess-3d
Icon=${ICON_NAME}
Terminal=false
Categories=Game;BoardGame;
Keywords=chess;board;3d;shadowfetch;
StartupNotify=true
StartupWMClass=Shadow Chess 3D
X-AppVersion=2.0.0
EOF
done

if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$PREFIX/applications" || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -f -t "$PREFIX/icons/hicolor" >/dev/null 2>&1 || true
fi
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$PREFIX/applications/${APP_ID}.desktop" || true
fi
test -x "$BINDIR/shadow-chess-3d"
echo "Installed $BINDIR/shadow-chess-3d"
echo "Desktop: $PREFIX/applications/${APP_ID}.desktop"
