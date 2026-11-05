---
story_id: 10.1a
title: Approved stone-brick maze walls
status: review
owner: CJX
reviewers: [DY, QZ]
---

# Story 10.1a: Approved stone-brick maze walls

See `docs/epic10-enhancements.md` for the three requested enhancement stories
and this slice's acceptance criteria. CJX approved the warm-stone preview on
2026-11-05. Only wall colours change in this slice.

## Implementation

- `brick_wall_pixel` uses 16x8 staggered courses and eight RGB444 colours.
  Dark mortar, lower/right shadow, upper/left highlights, four stone variants
  and sparse chips reproduce the approved software preview. Its 64x64 repeat
  needs only six low maze-coordinate bits; there is no texture RAM or new DSP.
- `render` evaluates that colour from the inverse-mapped maze pixel and registers
  it alongside the existing synchronous map read and flags. No extra pixel
  latency, RAM/address/protocol change, collision or UI change is introduced.
- Existing wall-colour expectations now use an independent integer-coordinate
  model. The focused runner covers texture, generated/top render, rotation,
  N=15/N=20 cameras, stage bounds, fog and WIN/LOSE overlays. The texture bench
  is included in the standard current-stories runner.
- Optional rotated-render capture emits complete 640x480 PPM frames at 0 and
  about 30 degrees. `brick_swatch.ppm` can be compared with the approved preview.
  Captures use the regression's fixed maze; their layout differs from the
  illustrative preview's DFS maze.

## Reproduce

Vivado 2025.2, repository root:

```tcl
source tb/run_story101a.tcl
```

This batch-oriented script runs nine benches and writes PPM frames under
`$env(TEMP)/story101a_brick_vivado_run`. The bench's capture parameter defaults
off in the standard suite. Build a fresh bitstream with
`vivado -mode batch -source scripts/build_bitstream.tcl`.

## Validation

Vivado 2025.2, 2026-11-05:

- `source tb/run_story101a.tcl`: **9/9 PASS**, exit 0. Texture checks all
  430,336 world pixels of the maximum 656x656 map plus the 4,096-pixel repeat.
- All 4,096 captured RGB swatch pixels exactly match the original approved
  Python preview. Full 0/30-degree frames were captured and visually inspected;
  see `docs/brick-wall-texture.png` (fixed regression layout, no top-level HUD).
- Rotation checks 881,357 pixels including 1,948 item pixels; N=15 camera checks
  244,413 pixels, and N=20 checks 244,333, including 6,660 far-map samples.
- Fog checks 965,120 pixels; WIN and LOSE check 420,000 pixels each. Stage bounds,
  generated/top-level maze colours and item masks also pass.
- `tb_render` had a pre-existing fixture mismatch after CUSTOM changed to
  N=5+SW[3:0]: it expected N=10 but drove SW[3:0]=0 (N=5). Set its fixture to
  `16'h4005` (fixed seed, N=10). No gameplay change was needed.
- `git diff --check` passes. No full current-stories suite PASS is claimed;
  this run is the nine-bench rendering-focused regression above.

- Fresh Basys 3 synthesis and routed implementation, RTL commit `413c60d`:
  setup WNS **+0.150 ns**, TNS 0; hold WHS **+0.048 ns**, THS 0; no failing
  endpoints. All 12,969 routable nets are fully routed, with no routing errors.
- Resources: 6,499 LUTs (31.25%), 7,375 registers (17.73%), 3.5 BRAM tiles,
  6 DSPs, 0 MMCM/PLL, within AD-8 caps.
- Routed checks: no unclocked registers, unconstrained internal endpoints,
  disconnected generated clocks or combinational loops. Both 100 MHz and
  6.25 MHz OLED clocks are present. Synthesis's generated-clock lookup warning
  does not persist as an unconstrained routed clock. Existing external I/O
  delay warnings remain; no new I/O constraint changes are part of this slice.
- Bitstream precondition DRC: **0 errors**.
- Bitstream generation **PASS**, build exit 0. The short-path project uses
  the repository build flow with only its output directory relocated.
  Local file: `C:/EE2026Projects/brick-wall-preview/Story10_1a_BrickWalls.bit`.
  Original build: `C:/EE2026Projects/build-story101a-20261105-185617/`.
  SHA256: `3D87A7B0F15B5D7ED37BDA476A6FE38DE6D21A1CBC9731F3E687D36B5324B6F9`.
  Reports are under `labyrinth.runs/impl_1` in that project; local build/sim logs
  are `C:/EE2026Projects/brick-wall-preview/story101a-{build,sim}.log`.

Board check is pending; no hardware PASS is claimed by the author.

## Board checklist (DY or QZ)

1. Program the recorded bitstream. Check EASY/MEDIUM/HARD/EPIC and representative
   CUSTOM sizes; walls use the approved warm stone, while floor/ball/markers and
   boxes remain distinct.
2. Rotate freely, then toggle SW15 snap. Bricks turn with the maze and stay
   fixed to each wall with no visible sliding, seams or flicker.
3. Move near each edge on HARD/EPIC so the camera pans, including far tiles
   32..40 on EPIC. Texture and wall edges stay aligned.
4. Bounce against horizontal/vertical walls and the outer border. Collision
   behavior is unchanged. Check boxes/fog, pause/resume, WIN and TIME UP.
5. Record branch/commit and PASS/FAIL with a short note or photo on the PR.
