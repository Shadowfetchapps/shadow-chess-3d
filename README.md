# Shadow Chess 3D

A premium desktop 3D chess game for Linux, built with Godot 4.7 and a presentation-independent rules engine.

## Run

**Exported binary**

```bash
~/src/ShadowChess3D/export/linux/shadow-chess-3d.x86_64
# or
~/.local/bin/shadow-chess-3d
```

**From Godot**

```bash
godot --path ~/src/ShadowChess3D
```

The editor is installed at `~/.local/opt/godot/Godot_v4.7.2-stable_linux.x86_64` and linked as `~/.local/bin/godot`.

**Desktop launcher** (not pinned): `~/.local/share/applications/shadow-chess-3d.desktop`

## Tests

```bash
~/src/ShadowChess3D/tools/run_tests.sh
```

## Export for Linux

Export templates for 4.7.2 must live in `~/.local/share/godot/export_templates/4.7.2.stable/`.

```bash
godot --headless --path ~/src/ShadowChess3D --export-release Linux ~/src/ShadowChess3D/export/linux/shadow-chess-3d.x86_64
```

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
