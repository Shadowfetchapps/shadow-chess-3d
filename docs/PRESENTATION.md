# Presentation

The look is a private salon at night: a single warm key light over a walnut table, gold on black, and a room that falls away into darkness.

## Scene

- **Table and room** (`SalonBuilder`): leather-topped walnut table with brass banding on a turned pedestal, Persian rug over a herringbone floor, damask walls with wainscot and brass rails, velvet drapes behind a brass-framed "SHADOWFETCH" plaque, and four brass floor lamps in the corners. The room is open above so the camera can rise freely.
- **Board** (`BoardView`): a moulded walnut-burl frame with a gold inlay and corner rosettes, 64 bevelled tiles, engraved coordinates that turn to face whoever sits at the bottom, and felt capture trays with brass rails on both sides.
- **Chess clock** (`ChessClockProp`): a working tournament clock on the table — live times, the running side's lamp lit and its button pressed.
- **Pieces**: Staunton-inspired meshes built by `tools/assetgen/build_models.py` in Blender. The knight is sculpted as a distance field (tapered muzzle, cheeks, eyes, nostrils, leaf ears, carved mane). Every piece has a separate gold `trim` surface.

## Materials and themes

`MaterialLibrary` creates shared materials once and restyles them in place, so switching theme never rebuilds the scene.

| Board theme | Squares | Frame | Inlay |
|---|---|---|---|
| Private Salon | maple / ebony | walnut burl | gold |
| Walnut Club | boxwood / rosewood | walnut | brass |
| Marble Hall | Carrara / Nero Marquina | verde marble | silver |
| Tournament | buff / green vinyl | matte black | — |

Piece sets: Ivory & Ebony (gold trim), Boxwood & Rosewood (brass), Marble (silver), Tournament Resin (no metal). Pieces use object-space triplanar grain so the pattern moves with the piece.

Squares use 1024² tileable albedo/normal/roughness sets; each tile shows one of four texture quadrants and alternates grain direction like an inlaid board, so no two neighbours look stamped.

## Light

- A warm key spotlight over the board with soft PCF shadows, a rim spot from behind the drapes, a faint cool fill, and a low bounce light.
- An HDR panorama of the room drives ambient light and reflections, so the gold, clearcoat, and ebony always have something to catch.
- AgX tone mapping, soft-light bloom on the lamps, and restrained exponential fog.
- Quality tiers: **Low** (no shadows or post), **Medium** (+shadows, bloom, fog), **High** (+SSAO, SSR, a box-projected reflection probe, far depth of field), **Ultra** (+SSIL, volumetric light, TAA). A 3D render-scale slider uses FSR below 100 %.

## Motion

- Moves glide on eased arcs; knights hop higher; castling slides the rook; captured pieces arc into the trays; promotions pop in.
- Selected pieces float; hovered pieces lift slightly; a checked king jolts over a pulsing red glow.
- Drag-and-drop lifts the piece to follow the cursor with a contact shadow left behind.
- **Reduce motion** in Settings removes arcs, bobbing, pulses, and the menu camera orbit.

## Marks

Two-tone marks read on pale and dark squares alike: legal moves are gold dots inside a dark outline, captures are rings, the selected square gets a soft wash with a brighter rim, the last move a warm tint, hover a thin gold frame, and hints a pale-blue arrow (knight hints bend like an L). *High-contrast highlights* strengthens all of them.

## Interface

Black glass panels, gold accents, Inter and Inter Display with tabular figures for clocks and move numbers, original SVG icons rasterised at 2× for sharp scaling, frosted-glass dialogs that blur the live frame behind them, and captured-piece rows rendered from the real 3D pieces.
