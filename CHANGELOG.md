# Changelog

## 2.0.0

- Rebuilt the table as a Shadowfetch private salon: dark wood, gold inlay, brass lamps, branded back wall, and a cinematic orbit camera.
- Replaced the cyan HUD with black-and-gold typography, active-clock highlighting, and a check-state status color.
- Upgraded ivory/ebony pieces with shared PBR materials, gold collars, and cached meshes so a move does not allocate a new set.
- Legal moves are gold discs, captures are rings, last-move and check use layered washes with a pulsing king square.
- Piece motion uses eased arcs, landing squash, capture particles, and the existing animation-speed setting.
- Hover highlighting uses a reused physics ray query.
- Quality tiers now drive bloom, SSAO, SSR, shadows, and a light far DOF on High.
- User-local install writes a real binary over the previous launcher.

## 1.0.0

- Desktop 3D chess with a presentation-independent rules engine
- Local and AI play, clocks, FEN/PGN, XDG saves
- Linux x86_64 export
