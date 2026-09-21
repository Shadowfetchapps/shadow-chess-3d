# Shadow Chess 3D

A premium desktop 3D chess game for Linux, built with Godot 4.7. Rules live in a presentation-independent engine; the board, salon, and HUD are a Shadowfetch black-and-gold flagship layer.

Version **2.0.0**.

## Run

**Installed binary**

```bash
~/.local/bin/shadow-chess-3d
```

**Exported binary**

```bash
./export/linux/shadow-chess-3d.x86_64
```

**From Godot**

```bash
godot --path .
```

Desktop launcher (not pinned): `~/.local/share/applications/com.shadowfetch.Chess.desktop`

## Tests

```bash
./tools/run_tests.sh
```

## Export and install

Export templates for 4.7.2 must live under the user Godot export-templates directory.

```bash
./tools/export_linux.sh
./tools/install-user.sh
```

`install-user.sh` writes the release binary to `~/.local/bin/shadow-chess-3d` and refreshes the desktop entry plus icons. Saves are kept if you later run `./tools/install-user.sh --uninstall`.

## Controls

- **LMB** — select and move
- **RMB** — orbit
- **Wheel** — zoom
- **MMB** — pan
- **H** — reset camera
- **F** — flip board
- **Esc** — pause

Saves and settings use XDG paths:

- `~/.config/shadow-chess-3d/settings.json`
- `~/.local/share/shadow-chess-3d/saves/`

## Presentation

All 3D art is original and generated at runtime. See `docs/PRESENTATION.md` and `docs/ASSETS.md`.

Screenshots in `docs/screenshots/` were captured from the running 2.0.0 game on Linux.
