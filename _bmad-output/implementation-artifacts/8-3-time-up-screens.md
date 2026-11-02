---
story_id: 8.3
story_key: 8-3-time-up-screens
title: TIME UP screens
status: review
owner: CJX
epic: 8
depends_on: [8.2]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/60
---

# Story 8.3: TIME UP screens

A timeout now has a visible result on both displays during the existing
approximately two-second LOSE hold, before the game returns to MENU.
Based on main `f7c8b90`, including countdown, HUGE/replay fixes and loop caps.

## Ownership and scope

The owner explicitly requested the full story in one PR, with DY reviewing
the graphics, on 2026-11-02. CJX implements OLED/status and the proposed VGA
panel/integration together. DY reviews `lose_overlay`, `render` and the top;
QZ reviews the status/fixture changes. This is the agreed pairing for this PR.

## Implementation

- `oled_status_text` adds a distinct LOSE page: stage name, TIME 00:00,
  TIME UP and BACK TO MENU. It cannot fall through to the menu page or show
  stale nonzero input time. The existing toggle mailbox applies this page
  only at an OLED frame boundary and restores the normal menu afterward.
- New `lose_overlay` uses the existing 5x7 font at 8x scale. White TIME UP
  text sits on a dark-red panel with red panel/screen outlines, visually
  distinct from the green WIN panel. Range tests, shifts and subtraction
  select the glyph; no per-pixel multiplier, divider or framebuffer is added.
- `render` captures `lose_frame` alongside WIN/trig in vertical blanking.
  Overlay flags and font data match the existing one-clock pixel pipeline.
  TIME UP takes priority over the ball/map; the frozen maze stays behind it.
- The top enables rendering/maze reads in LOSE and masks MENU/GENERATE as
  before. Reset clears the overlay. WIN rendering, countdown, deadline
  priority, physics freeze, menu selection retention and LOSE hold duration
  retain their existing behavior. No shared state/port widths change.

## Simulation

Run from the repository root in Vivado 2025.2:

```tcl
set repo [pwd]
source [file join $repo tb run_story83.tcl]
source [file join $repo tb run_current_stories.tcl]
```

- `tb_lose_render`: all 800x525 = 420,000 raster positions are compared with
  independently written row bitmaps and geometry, including active/blanking,
  one-clock sync, all TIME UP glyphs, spaces, edges, panel/rim colors and
  priority over a ball. Checks no overlay change before the frame snapshot,
  LOSE -> WIN -> LOSE -> PLAY transitions and reset removal. Existing WIN
  pixel/model tests remain in the full regression.
- `tb_top_story83_time_up`: real debounced menu, generator, timer, controller
  and OLED CDC mailbox. EASY and HARD count down naturally to zero, enter
  LOSE on a frame boundary, show actual white glyph/red rim at the top's VGA
  pins, freeze rotation, keep the selected stage, transfer TIME UP without
  tearing the active OLED frame, hold for the configured frames and restore
  MENU on both displays. Short and long CENTER reset work from LOSE; long
  release never confirms a new game. Only frame boundaries and seconds are
  abbreviated; expiry, generation and mailbox handshakes are real.
- Formatter checks include EASY/HARD/HUGE LOSE labels, zero time even if its
  inputs contain a stale nonzero value, and removal on MENU. The state-width
  bench distinguishes valid LOSE from still-unused codes 5..7.

## Validation

Vivado 2025.2 on 2026-11-02, full `My_Top_Module`, Basys 3
`xc7a35tcpg236-1`, implementation commit `5ca5d52`:

- Focused four-bench suite: PASS, including the complete 420,000-pixel raster.
- Fresh synthesis, implementation and bitstream generation: PASS, no errors
  or critical warnings. Bitstream DRC: 0 errors. The ordinary implementation
  warning is reset-activity power estimation, not a timing violation.
- Routed WNS **+0.635 ns**, WHS **+0.102 ns**, TNS/THS **0.000 ns**;
  all user-specified timing constraints met.
- Resources: **3,671 LUTs** (17.65%), **3,810 registers** (9.16%),
  **3 BRAM tiles**, **6 DSPs**, **0 MMCM / 0 PLL**, within AD-8.
- Build/report directory: `C:/EE2026Projects/build-story83-f7c8b90`.
  The isolated RTL snapshot matches this branch byte for byte.
- Bitstream SHA-256:
  `A548FB40BE36813FA6E322B171040E38CC314A9510CA76746AD86DCBA7908079`.
- Full `tb/run_current_stories.tcl` regression: **40/40 simulation runs PASS**
  (38 core benches plus both nominal-frequency OLED driver modes), exit 0.
  Existing WIN, rotation, maze/camera/physics, reset, menu and countdown
  scenarios all pass alongside the new TIME UP raster/integration checks.
- `git diff --check`: PASS.
- Hardware verification remains pending.

## Non-author board checklist

QZ or DY must record PASS/FAIL, the tested commit and a photo or note before
approval/merge under `docs/parallel-workstreams.md` section 7.3. No hardware
PASS is claimed by CJX, the story author.

1. Program `C:/EE2026Projects/build-story83-f7c8b90/labyrinth.runs/impl_1/My_Top_Module.bit`.
2. Select EASY (01:00); compare the countdown with a watch. At 00:00 the
   monitor shows white TIME UP with a red panel/outline and the OLED shows
   the matching TIME UP / TIME 00:00 page. The ball/rotation remain frozen.
3. After approximately two seconds the stage menu returns, the VGA panel
   clears and the OLED shows the menu without mixed/stale text.
4. Repeat on HARD (02:00). Check the same timeout behavior on HUGE if time
   permits. Automatic timeout retains the selected menu stage.
5. During LOSE check short CENTER returns to MENU immediately, and long
   CENTER resets the OLED/game without starting a new stage on release.
6. Recheck a normal WIN: green panel, TIME LEFT value and automatic replay
   still work; no TIME UP panel appears in MENU, GENERATE, PLAY or WIN.

Generated logs/reports/bitstreams remain outside source control.
