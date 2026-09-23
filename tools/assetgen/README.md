
## Audio

`gen_audio.py` synthesises every sound effect and the music loop from scratch
(numpy/scipy DSP only -- no samples, no network) and writes Ogg Vorbis files
(`libvorbis -q:a 5`, 44.1 kHz) to `assets/audio/`.

```sh
python3 tools/assetgen/gen_audio.py                  # render all + QC table (~1.5 min)
python3 tools/assetgen/gen_audio.py --only move_1 check
python3 tools/assetgen/gen_audio.py --analyze-only   # QC existing files only
python3 tools/assetgen/gen_audio.py --plots /tmp/sfx # + waveform/spectrogram PNGs
```

Needs Python 3 + numpy + scipy and `ffmpeg` built with libvorbis (matplotlib
only for `--plots`). Output is **deterministic**: each sound has its own RNG
seeded with `crc32("chess:<name>")` and ffmpeg runs bit-exact, so a re-run
produces byte-identical files.

**Techniques.** Pieces use modal synthesis: a unit-momentum raised-cosine contact
pulse (width = felt softness) excites a bank of inharmonic boxwood modes
(T60 = 2.2 / (loss x f)), a denser set of walnut-board plate modes and a
100-125 Hz body thump; felt "puff" and grain noise add surface detail. Every
variant randomises pitch, mode ratios, damping, strike position and sometimes a
second "rock" contact. Musical cues are additive celesta (struck-bar partials
1 : 2.76 : 5.40 : 8.93), a church-bell partial set (hum, prime, minor tierce,
quint, nominal) and a felt piano (stiff-string inharmonicity, two detuned
strings, two-stage decay). Everything passes through a small synthetic room
(early reflections + two-band exponentially decaying noise tail).

**Levels.** SFX are normalised to a target max-momentary loudness with a
true-peak ceiling; the move family anchors the set at -3 dBFS peak
(about -21 LUFS momentary, dual-mono). Variants in a family are loudness-matched
(spread < 0.5 LU). UI sounds sit 11-21 LU below moves. Every file is checked
after encoding: true peak <= -1 dBTP. The music loop is -20 LUFS integrated.

**Integration notes.**
- `music_salon.ogg` is a seamless loop of exactly 5 292 000 samples (120 s,
  16 chords x 7.5 s at 64 BPM). It is rendered circularly (note and reverb
  tails wrap into the head), so loop the **whole file** (`loop = true`,
  `loop_offset = 0`). The file starts mid-texture, so fade it in.
- SFX start with 4 ms of digital silence (this keeps Vorbis pre-echo off sample
  0) and end with 12 ms of silence.
- `check` and `checkmate` already contain a placement, so play them *instead
  of* `move_N`, not on top of it. `promote` is only the shimmer and is meant to
  follow the move sound.
- SFX are mono. Musical cues (`check`, `checkmate`, `draw`, `promote`,
  `game_start`, `hint`, `puzzle_solved`, `victory`, `defeat`) and the music are
  stereo.

| file | design |
|---|---|
| move_1..4 | felt-bottomed boxwood piece on a walnut board: soft contact, ~1 kHz "tock", board body and thump. 2 and 4 rock once onto the base |
| capture_1..3 | bigger piece set down harder (less felt, more board and thump), then the displaced piece clacks (hard wood-on-wood, no board) 16-26 ms later |
| castle | king (larger, lower) then rook 155 ms later |
| check | placement plus a soft celesta dyad A5/D6 |
| checkmate | heavy placement, low church bell on D (minor tierce) and a rolled Dm chord on celesta, 1.7 s room |
| draw | celesta Dsus4 resolving to an open fifth (no third, neutral) |
| promote | fast celesta run A5-B5-D6-E6-A6 over D5, with faint glass grains |
| illegal | muted low double thud (piece put back), low-passed at 900 Hz |
| select | tiny felt scuff and a light tap as the piece is lifted |
| ui_click / ui_hover | short damped modal ticks (1.6-5.6 kHz) with a small body; hover is almost subliminal |
| ui_open / ui_close | air swell sweeping up (open) or down (close) with a soft tick |
| game_start | soft low bell (D) over a celesta D3 and a quiet fifth |
| clock_tick | brass escapement tick with a small wooden case resonance |
| clock_warning | two soft muted celesta pings on A5 with a tick |
| hint | two soft celesta notes A5 and E6 with a hint of glass |
| puzzle_solved | rising D5-A5-B5-E6 (bright Dorian colour) over a soft bell |
| puzzle_wrong | two muted wooden marimba notes falling A3 to F3 |
| victory | plagal cadence G(add9) to D6/9 on celesta, with a low bell and a pad swell |
| defeat | felt-piano Bbmaj9 easing into Dm(add9) over a soft pad. Consoling, not sad |
| music_salon | D Dorian, 64 BPM: slow additive pad (detuned, brightness breathing on slow LFOs), sparse felt-piano melody, soft sub, 3.2 s dark hall |

## Models

`build_models.py` generates every 3D model in Blender from code (no external
assets, no network) and writes Wavefront OBJ + MTL files to `assets/models/`.
The same file lives in Shadow Checkers; keep the two copies identical. The
script detects which set to build from `project.godot` (`--game` overrides).

```sh
blender -b --factory-startup --python tools/assetgen/build_models.py                 # build + validation table (~12 s)
blender -b --factory-startup --python tools/assetgen/build_models.py -- --only knight
blender -b --factory-startup --python tools/assetgen/build_models.py -- --preview /tmp/models   # + EEVEE contact sheets
blender -b --factory-startup --python tools/assetgen/build_models.py -- --no-build --preview /tmp/models
```

Needs Blender 5.2+ (tested with 5.2.1). It uses the numpy and openvdb bundled
with Blender. Output is **deterministic**: a re-run writes byte-identical files.

**Conventions (as stored in the OBJ, i.e. Godot space).**
- 1.0 = one board square, +Y up.
- Pieces: origin at the centre of the base, with the base bottom at y = 0.
- The knight's snout points to **-Z**. The bishop's slit opens toward +Z.
- Every piece has `usemtl body` first, then `usemtl trim` (gold accents). So
  surface 0 = body and surface 1 = trim. Tiles and the base slab are body only.
- Smooth normals are split at crisp edges (smooth-by-angle 35 deg) and
  face-area weighted, so big faces stay flat next to small fillets.
- UVs are cylindrical on lathed parts, and U along the side with V along the
  profile on the frame. The tile's top is planar 0..1.
- Faces are triangles and planar quads only; n-gons are triangulated because
  Godot fans them.
- The `.mtl` colours (ivory and gold) are placeholders; the game overrides them.

| file | tris (trim) | height x base diameter | notes |
|---|---|---|---|
| pawn.obj | 9 088 (1 536) | 0.64 x 0.44 | base, tapered stem, collar, sphere head |
| rook.obj | 9 164 (1 536) | 0.74 x 0.50 | flared, hollowed turret, 5 boolean crenels |
| knight.obj | 18 806 (1 536) | 0.86 x 0.50 | sculpted head (see below), snout -Z |
| bishop.obj | 10 630 (2 064) | 0.94 x 0.50 | teardrop mitre, boolean diagonal slit, gold ball finial |
| queen.obj | 11 952 (2 176) | 1.06 x 0.54 | double collar, trumpet crown, 8 coronet points with gold balls |
| king.obj | 11 324 (1 724) | 1.20 x 0.56 | crown band and dome, bevelled gold cross (arms along X) |
| square_tile.obj | 28 | 1.0 x 1.0 x 0.07 | top at y = 0.07, 0.01 rounded top edge |
| board_frame.obj | 8 136 (7 712) | 9.2 x 9.2, y -0.12..0.10 | ogee moulding, 8.0 x 8.0 opening, gold inlay stripe and 4 rosettes |
| board_base.obj | 12 | 8.0 x 8.0 x 0.10 | slab under the squares, top at y = 0 |

**Techniques.**
- Lathed pieces revolve a 2D profile (`Profile`: lines, cubic Beziers,
  arcs, automatic fillets, crease flags) at 64 segments. Pieces share a
  weighted base: felt-pad chamfer, plinth, ovolo, and a seat for the gold
  bead.
- Crenels, the bishop's slit and the coronet notches are Manifold booleans.
- The knight is a signed-distance-field sculpt:
  - The side silhouette (a Catmull-Rom curve) is extruded with a variable
    width and rounded edges.
  - Cheeks, brow, eyes, nostrils, ears and a forelock are smooth-blended in,
    with a chevron-carved mane along the back of the neck and an engraved
    mouth line.
  - OpenVDB meshes it at 2.5 mm voxels, it is decimated to about 13.5k
    tris, then boolean-unioned onto the lathed base and collar.
- The frame profile is swept around the 8 x 8 opening with mitred corners.
- Gold trims are separate closed shells set 1.5-3.5 mm proud of the body:
  bead rings, collar bands, the inlay stripe and rosettes. They are never
  coplanar with a body face, so they cannot z-fight.

**Validation.** Every run prints a table and flags FAIL on any problem:
- usemtl order
- non-manifold edges
- positive signed volume (outward normals)
- flipped faces
- normals and UVs present
- the knight's snout pointing to -Z

## Textures

`gen_textures.py` generates every PBR texture set and the HDR environment
panorama procedurally (numpy/scipy/Pillow only -- no photos, no network) and
writes them to `assets/textures/`. The same file lives in both Shadow Chess 3D
and Shadow Checkers; keep the two copies identical. The game is detected from
`project.godot` (`--game chess|checkers` overrides).

```sh
python3 tools/assetgen/gen_textures.py                      # everything (~1 min, 8 processes)
python3 tools/assetgen/gen_textures.py --only sq_maple,env  # a subset ('env' = the HDR)
python3 tools/assetgen/gen_textures.py --preview-dir /tmp/texqc   # + QC preview sheets
python3 tools/assetgen/gen_textures.py --selftest           # periodicity + HDR round-trip tests
```

Output is **deterministic** (every material has its own RNG seeded from
`crc32(name)`; re-runs are byte-identical) and **seamlessly tileable**: all
noise is periodic spectral noise (integer frequencies per tile), periodic
Worley noise or analytic patterns with integer periods, sampled through
periodic domain warps. `--selftest` checks that every primitive gives the same
value one whole tile away. Every run prints a table with file sizes, mean
albedo, roughness range and a seam check (`seam` = difference of the
wrap-around pixel pair / mean interior neighbour difference, ~1 = seamless;
`rank` = share of interior neighbour pairs at least as different -- a real
seam would be the worst pair, 0%; values of 2-3 with rank > 0 are texture
content, e.g. a vein or ring line running along the tile edge).

**Per material `<name>`:**
- `<name>_albedo.jpg` -- sRGB base colour, JPEG q92. Linear albedo is kept
  in a plausible range (darkest dyes/woods ~0.015-0.02 linear, whites <= ~0.8).
- `<name>_normal.png` -- tangent-space normal, **OpenGL convention (green =
  +Y up)**, which is what Godot expects. Baked from a height field with the
  intended strength, so start with `normal_scale = 1.0`.
- `<name>_rough.jpg` -- greyscale roughness (white = rough). Use
  `roughness_texture_channel = GRAYSCALE` (or RED) with `roughness = 1.0`.
- 1024^2 unless noted, piece finishes 512^2, floors and rug 2048^2.
- Everything is `metallic = 0` except `brass_brushed` (`metallic = 1`, the
  albedo is the brass F0 colour).
- Wood grain always runs along **U** (texture x). Board squares are designed
  so one square shows the whole tile (UV 0..1); random offsets and 180-degree
  flips are safe. 90-degree rotations turn the grain across the square.
- Import settings: for 3D use make sure the textures import as *VRAM
  Compressed* with *mipmaps* on, and the `_normal` maps with
  `compress/normal_map = Enable` (Godot's detect-3D usually does this the
  first time a texture is used on a 3D material).

**Techniques.** Wood: growth-ring contour `rings*y + warp(x,y)` with a large,
x-elongated domain warp (gives straight grain that occasionally forms flat-sawn
cathedral arches), ring-width jitter, per-ring darkness, asymmetric
earlywood/latewood profile anti-aliased by the ring gradient; thin grain lines
are zero sets of x-elongated noise; pores are elongated Worley cells (dense in
earlywood for ring-porous oak), medullary ray flecks, mineral streaks, ribbon
figure (mahogany). Fibres use a coordinate that only loosely follows the ring
warp so nothing stretches where arches fold. Burl: three-level domain warp +
clustered Worley "eyes" with rings wrapped around them. Marble veins: zero set
of a low-frequency, strongly anisotropic field pushed through a fractal domain
warp (long, jagged, branching veins without little closed loops), plus
secondary veins near the primaries, warped Voronoi crack webs and cloudy
ground. Floors: exact herringbone lattice at 45 degrees / staggered courses;
every plank samples a different region, flip and tint of a large periodic
wood field; bevels and gaps are in the height/roughness. Damask: symmetric
ornament (pomegranate, palmette crown, acanthus scrolls, berries) drawn from
Bezier/spiral polygons on a half-drop lattice, satin (weft) vs matte (warp)
weave in roughness/normal. HDR: a small analytic room renderer (box room,
point/area lights with lobes, emissive lamps/windows) written as
Radiance RGBE with per-channel RLE and verified by reading it back.

**Shadow Chess 3D material notes** (roughness min / mean / max as generated;
"tile" = suggested world size of one 0..1 UV repeat):

| material | use | roughness | notes |
|---|---|---|---|
| `sq_salon_light` | salon light square: pale cream hard maple, fine wavy grain, satin | 0.27 / 0.37 / 0.50 | one square = one tile |
| `sq_salon_dark` | salon dark square: Gabon-style ebony, faint brown-black streaks, polished | 0.05 / 0.13 / 0.23 | optional clearcoat 0.3 |
| `frame_walnut_burl` | salon frame: lacquered walnut burl, eye clusters | 0.13 / 0.14 / 0.24 | tile ~0.25 m; clearcoat 0.5-1 looks right |
| `sq_boxwood` | walnut theme light square: warm yellow boxwood, tight grain | 0.29 / 0.39 / 0.51 | |
| `sq_rosewood` | walnut theme dark square: Indian rosewood, purple-brown, dark streaks, open pores | 0.21 / 0.33 / 0.58 | |
| `frame_walnut` | walnut theme frame: straight-grain walnut | 0.25 / 0.37 / 0.70 | tile ~0.3 m, U along the rail |
| `sq_marble_white` | Carrara: grey feathered veins, cloudy ground, polished | 0.02 / 0.07 / 0.26 | normal_scale 0.5-1 |
| `sq_marble_black` | Nero Marquina: crisp white veins + hairline web | 0.02 / 0.07 / 0.16 | |
| `frame_marble_green` | Verde Guatemala-style serpentine, dense pale vein web | 0.02 / 0.08 / 0.16 | tile ~0.3 m |
| `sq_vinyl_buff`, `sq_vinyl_green` | tournament roll-up board: flat colour, fine stipple, faint fabric emboss | 0.65 / 0.71 / 0.78 | |
| `frame_matte_black` | tournament frame: matte black paint, soft orange peel | 0.52 / 0.64 / 0.74 | |
| `floor_herringbone` (2048) | dark oak herringbone parquet at 45 deg, visible gaps/bevels | 0.27 / 0.44 / 0.94 | tile ~1.4 m (planks ~6.6 x 33 cm) |
| `wall_damask` | wine/charcoal damask, satin ornament on matte ground | 0.41 / 0.74 / 0.89 | tile ~0.6 m (motif ~48 cm) |
| `rug_persian` (2048, not tileable) | single dark rug: medallion, spandrels, 3 borders, bound edges | 0.74 / 0.88 / 1.00 | UV 0..1 over the whole (square) rug, e.g. 2.4 x 2.4 m |
| `felt_black` | piece-bottom felt / cloth | 0.90 / 0.91 / 0.95 | tile ~0.1 m, normal_scale 0.5-1 |
| `brass_brushed` | brass fittings, lamps, clock (metallic 1) | 0.15 / 0.31 / 0.49 | brushing along U, tile ~0.15 m |
| `leather_black` | chair / table leather: pebble grain + creases | 0.37 / 0.50 / 0.75 | tile ~0.35 m |
| `piece_ivory` | warm ivory with faint Schreger cross-hatching | 0.22 / 0.23 / 0.27 | triplanar, tile ~6 cm (`uv1_scale` ~16) |
| `piece_ebony` | near-black ebony, faint grain | 0.06 / 0.13 / 0.22 | triplanar |
| `piece_boxwood`, `piece_rosewood` | wood piece sets | 0.29-0.50 / 0.22-0.58 | triplanar |
| `piece_marble_white`, `piece_marble_black` | marble piece sets | 0.02 / 0.07 / 0.22 | triplanar |

**`env/salon.hdr`** -- 2048x1024 equirectangular Radiance HDR (RLE RGBE),
dim private salon: dark wine damask walls with dark wainscot and a gilt dado
rail, four brass wall sconces (shade ~16, bulb core 40) casting warm pools up
and down the walls, a warm overhead softbox (~4.5, straight up), a cool
window with mullions and wine curtains (~1.6) on +X, a bookcase on -X,
paintings in gilt frames between the sconces on +/-Z, dark herringbone floor
with a rug and a dark table top just below the viewpoint. Solid-angle mean
luminance ~0.09, peak 40. Mapping follows Godot 4's panorama lookup
(u = atan2(x, -z)/2pi, v = acos(y)/pi): the image edges face -Z (Godot's
forward), the centre +Z, u = 0.25 is +X. Use it via
`PanoramaSkyMaterial.panorama` with `ambient_light_source` and
`reflected_light_source` = Sky; start with `energy_multiplier = 1` and rotate
with `Environment.sky_rotation.y` if the window should sit elsewhere.
