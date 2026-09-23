# Changelog

## 3.0.0 — Flagship

### Shadow, the engine
- New self-contained search on a 0x88 board with integer moves: iterative deepening, aspiration windows, PVS, transposition table, null-move pruning, late-move reductions, futility pruning, check extensions, killer/history ordering, and quiescence.
- Tapered PeSTO evaluation with pawn structure, bishop pair, rook files, and king shelter.
- Six levels (Beginner ~600 to Master ~2100) with human-like mistakes at the low end and a weighted opening book.
- Runs on a worker thread and can be cancelled instantly — the board never freezes (2.0 searched on the UI thread).
- Clock-aware time budgeting in timed games.

### Rules and notation
- Threefold repetition, insufficient material with same-coloured bishops, and the FIDE timeout-vs-bare-king draw.
- Zobrist hashing throughout; FEN validation with clear errors; a failed FEN load leaves the game untouched.
- Robust SAN parsing; PGN import with comments, NAGs, variations, and SetUp/FEN starts; PGN export wrapped at 80 columns with correct numbering for Black-first starts.

### New modes
- **Puzzles**: 36 original checkmate puzzles (mate in 1, 2, 3), verified by the test suite; any forcing solution is accepted.
- **Analysis board** with a live evaluation bar and Shadow's principal variation.
- **Game review**: step through any game from the scoresheet or with the arrow keys.
- **Hints**, **draw offers** that Shadow judges on the position, **rematch** and **swap colours**.
- **Statistics** and an Elo-style rating against Shadow's levels.
- **Continue** your last game from an autosave.
- Time controls with increments (1+0 to 30+0), low-time warnings.
- Typed moves in SAN or UCI.

### Look and feel
- Blender-built Staunton set with a sculpted knight; moulded board frame with gold inlay; bevelled tiles.
- Procedural 1K PBR textures and an HDR room panorama for reflections; four board themes and four piece sets that switch live.
- Rebuilt salon: leather-topped walnut table, herringbone floor, Persian rug, damask walls, brass floor lamps, and a working chess clock.
- AgX tone mapping and an Ultra tier with SSIL, volumetric light, and TAA.
- Drag-and-drop, capture trays, eased arcs, promotion pop, check glow, hint arrows, two-tone legal-move marks.
- Camera frames the board in the space the HUD leaves free, with smooth damping, keyboard orbit/zoom, and a top-down view.
- New HUD: player cards with clocks and rendered captured pieces, a clickable scoresheet, status pill, toasts, frosted-glass dialogs, original icon set.
- Settings, help, and pause are overlays — opening them no longer abandons the game.
- Original synthesised audio: varied wooden placements, captures, check and mate bells, UI ticks, and an ambient score on separate Music/SFX/UI buses.
- Reduce-motion, high-contrast marks, and interface scaling.

### Under the hood
- Versioned settings (schema 3) with migration from 2.0 and corrupt-file recovery.
- Save format v2 stores the start position and full move list; 2.0 saves still load.
- Test suites grew from 113 to over 550 checks, including an end-to-end drive of the game controller.
- Reproducible asset pipeline in `tools/assetgen/`.
- MIT licence.

## 2.0.0

- Rebuilt the table as a Shadowfetch private salon: dark wood, gold inlay, brass lamps, branded back wall, and a cinematic orbit camera.
- Black-and-gold HUD, active-clock highlighting, check-state status colour.
- Shared PBR materials, cached meshes, eased move arcs, capture particles.
- Quality tiers for bloom, SSAO, SSR, shadows, and DOF.

## 1.0.0

- Desktop 3D chess with a presentation-independent rules engine.
- Local and AI play, clocks, FEN/PGN, XDG saves.
- Linux x86_64 export.
