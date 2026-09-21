# Presentation

Everything visual is generated at runtime. No commercial chess-set meshes.

- `MaterialLibrary` — cached PBR ivory, ebony, gold, oak, charcoal stone, and highlight materials. Wood and stone albedo come from small procedural images built once.
- `SalonBuilder` — dark salon, columns, drapes, pedestal, brass lamps, and gold TextMesh branding.
- `BoardView` — raised squares, gold inlay frame, layered last-move / legal / capture / check / hover marks.
- `PieceMeshBuilder` — original KQRBNP silhouettes with gold trim. Prototypes are duplicated so meshes and materials stay shared.
- `PieceView` — select bob, landing squash, check pulse.
- `OrbitCamera` — 36° FOV, orbit / pan / zoom, optional far DOF on High.
- `WorldLook` — ACES, quality-tier bloom, SSAO, SSR, and restrained fog.
- `BoardVFX` — reused GPU particle bursts for capture and landing.
- `ThemeFactory` / HUD — black panels, gold borders, Inter typography.

Animation duration is `0.26 / animation_speed`. Input is ignored while a move is in flight so the engine and the board cannot desync.

Squares stay readable on purpose: cream oak versus charcoal stone, ivory versus near-black pieces, gold used for trim and marks rather than piece bodies.
