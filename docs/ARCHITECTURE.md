# Architecture

Shadow Chess 3D is a Godot 4.7 (Forward+) project written in typed GDScript. Everything that decides the game — rules, notation, the Shadow engine, puzzles — lives in pure `RefCounted` classes that never touch the scene tree, so the headless test suites can exercise them directly and the AI can run on worker threads.

```
scripts/
  chess/      rules: ChessTypes, ChessMove, ChessEngine, Fen, San, Pgn, ChessPuzzles
  ai/         Shadow: ChessAI (levels, SearchJob, opening book) + ChessSearch (fast board)
  game/       GameController (the live game), GameSession (menu → game hand-off)
  board/      BoardView (tiles, frame, marks, trays), SalonBuilder (room), ChessClockProp
  pieces/     PieceMeshBuilder (OBJ meshes + fallback), PieceView (motion cues)
  gfx/        MaterialLibrary (themes, marks), WorldLook (environment, lights, quality)
  camera/     OrbitCamera (damped orbit, HUD-aware framing)
  audio/      AudioManager (buses, sample variants, music)
  save/       SettingsStore, ProfileStore, SaveManager
  ui/         ThemeFactory, IconLibrary, widgets/ (UIKit, Modal, ToastLayer, PlayerCard,
              MoveList, EvalBar, PieceIcons), screens and dialogs
data/         opening_book.txt, puzzles.json
tests/        test_runner.gd (engine, AI, PGN, puzzles) and scene_runner.tscn (presentation)
tools/        run_tests.sh, export_linux.sh, install-user.sh, capture_screenshots.sh,
              check_scripts.gd, assetgen/ (Blender models, audio, textures)
```

## Autoloads

| Autoload | Role |
|---|---|
| `SettingsStore` | Versioned settings (schema 3) in `$XDG_CONFIG_HOME/shadow-chess-3d/settings.json`. Migrates 2.0 files, clamps and validates every field, moves an unreadable file aside, applies display and audio settings. Emits `settings_changed`. |
| `ProfileStore` | Rating and records in `$XDG_DATA_HOME/shadow-chess-3d/profile.json`: results per Shadow level, an Elo-style rating against each level's nominal strength, puzzle progress, lifetime counters. |
| `GameSession` | What the next game scene should start: mode (`LOCAL`, `AI`, `PUZZLE`, `ANALYSIS`), sides, Shadow's level, clock, save path, pending FEN/PGN, puzzle. |
| `AudioManager` | Creates `Music`, `SFX`, and `UI` buses, loads `assets/audio/*.ogg` with numbered variants, rotates variants, pools voices, crossfades the music loop, and falls back to procedural tones if a file is missing. |

## Scenes

- `scenes/menus/main_menu.tscn` — `MenuBackdrop` (the salon with Morphy's Opera Game replaying) plus the menu column and its dialogs.
- `scenes/main/game.tscn` — `World` (`GameController`, a `Node3D`) and `UI` (`game_ui.gd`, a `CanvasLayer`). Settings, help, pause, promotion, and the result card are overlays inside the game scene, so opening them never loses the game.
- `tests/scene_runner.tscn` — presentation tests that need autoloads.

## The live game (`GameController`)

- **Engine**: one `ChessEngine` holds the whole game (history, redo stack, Zobrist key, repetition list). The board shows `view_ply`, which equals the history length when live; reviewing rebuilds a cached position by replaying the first `view_ply` moves from `start_fen`.
- **Input**: physics ray picks against square bodies (layer 1) and piece bodies (layer 2). A press selects; moving more than 7 px turns it into a drag that follows the cursor on a plane above the board; release on a legal square plays, anywhere else snaps back. Click-click still works. Promotions open the picker (or auto-queen).
- **Animation**: moves are tweened with eased arcs (knights hop higher), castling slides the rook, captures fly into the felt trays beside the board, promotions swap the mesh with a pop. The move sound fires on landing; check and checkmate cues replace the move sound.
- **Threads**: Shadow's move, the evaluation bar, hints, and puzzle checks each run as a `WorkerThreadPool` task. Jobs are plain data objects (`ChessAI.SearchJob`, `FuncJob`) that receive the start FEN and move list, never live nodes. The controller polls completion in `_process`, waits on every task it starts, and cancels (sets `cancelled`, then waits) on undo, restart, or scene exit.
- **Clocks**: base + increment, running from the second move, paused while the pause menu is open. A flag loses unless the opponent cannot mate (FIDE), which the engine scores as a draw.
- **Autosave**: after every move the game is written to `saves/autosave.json`; the menu offers *Continue* when it holds an unfinished game.

## Save format (v2)

```json
{
  "format": "shadow-chess-save", "version": 2, "app_version": "3.0.0",
  "mode": "ai", "ai_side": 1, "ai_level": "club",
  "white_name": "You", "black_name": "Shadow",
  "start_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
  "moves_uci": ["e2e4", "e7e5"],
  "result": "*", "finished": false,
  "clock": {"base": 600, "increment": 0, "white": 598.2, "black": 600.0, "enabled": true},
  "pgn": "[Event \"Shadow Chess 3D\"] …"
}
```

Loading replays `moves_uci` from `start_fen`, so undo and review work after a reload. Version 1 files from 2.0 (`history_uci` + `fen`) are converted on read.

## Rendering

- `MaterialLibrary` creates every material once. `apply_theme(board, pieces)` mutates them in place, so changing the board theme or piece set restyles the live scene with no rebuild. Four board themes × four piece sets.
- Board squares use 1024² tileable PBR sets (albedo, normal, roughness). Each square picks one of four UV quadrants and a rotation so no two neighbours repeat; grain alternates direction like an inlaid board.
- Pieces are Blender-built OBJ meshes with `body` and `trim` surfaces; piece materials use object-space triplanar grain.
- `WorldLook` uses an HDR panorama of the room for ambient and reflected light (so metals and lacquer have something to reflect), AgX tone mapping, and quality tiers: Low (no shadows/post), Medium (+shadows, bloom, fog), High (+SSAO, SSR, reflection probe, far DOF), Ultra (+SSIL, volumetric light, TAA).
- `OrbitCamera` frames the board inside the area the HUD leaves free, using a lateral lens offset, and eases toward goal yaw/pitch/distance every frame.

## UI

`ThemeFactory` builds one shared `Theme` with type variations (`PrimaryButton`, `GhostButton`, `IconButton`, `ChipButton`, `MoveButton`, `MainMenuButton`, `Card`, `Modal`, `Pill`, `Toast`, …). `IconLibrary` rasterises original 24-px stroke icons from SVG at 2× for crisp scaling. `Modal` dialogs blur and tint the live frame behind them with a screen-texture shader. `PieceIcons` renders the real 3D pieces into thumbnails in one off-screen pass so captured-piece rows and the promotion picker always match the current set.

## Tests

`./tools/run_tests.sh` runs two headless entry points:

1. `tests/test_runner.gd` (`--script`) — rules (perft on several reference positions, special moves, draws, FEN validation, Zobrist), SAN/PGN round trips, AI behaviour and threading, opening-book legality, and every puzzle's solution and uniqueness.
2. `tests/scene_runner.tscn` — presentation: material caching and in-place theme switching, piece construction, settings migration and validation, save-format migration, rating maths, theme and icon building.

`godot --headless --path . --script res://tools/check_scripts.gd` loads every script to surface parse errors in one pass.
