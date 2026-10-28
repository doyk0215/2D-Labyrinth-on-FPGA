---
story_id: 3.3
story_key: 3-3-reach-the-goal-win-and-play-again
title: Reach the goal, win, and play again
status: in-progress
owner: QZ + CJX (win indication)
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/22
---

# Story 3.3: Reach the goal, win, and play again

## CJX visual part

- [x] Wire the existing two-bit `game_state` contract into `render`.
- [x] Snapshot WIN during vertical blanking with the renderer's angle/trig
  snapshot, so the indication cannot change partway through a displayed frame.
- [x] Draw a fixed screen-space `YOU WIN` panel and green outline above the
  maze and ball, using the existing registered 5x7 `font_rom` at 8x scale.
- [x] Keep render reads and the completed maze visible in PLAY and WIN.
  MENU and GENERATE continue to hide the map and disable render reads.
- [x] Clear the indication on reset and when the next displayed frame leaves WIN.
- [x] Add pixel-level and top-level visual integration benches to the regression.

The red bottom-right cell is the start; the green top-left cell is the goal.
The indication consumes `game_state == 2'b11`; it does not decide whether the
ball has won or how long WIN lasts.

## QZ control part still required

- [ ] Detect the ball centre entering the goal tile and connect the controller's
  `in_goal` input, which is still tied low in `My_Top_Module` on current main.
- [ ] Hold WIN for about two seconds (approximately 120 VGA frame ticks), then
  generate a fresh maze and initialize the ball at the red start tile.
- [ ] Verify the full scripted goal-to-WIN-to-new-maze path and the pause duration.
- [ ] Run the combined hardware check before closing issue #22.

The existing controller skeleton advances from WIN to GENERATE on its next
frame tick. This PR completes CJX's visual part; the whole story remains open.

## Verification

`tb/run_story33_visual.tcl` runs both new benches with Vivado 2025.2 and the
real VHDL mouse controller. `tb/run_current_stories.tcl` includes them alongside
the existing VGA, rotation, collision, menu/settings, and OLED checks.

- `tb_win_render`: all 420,000 positions of an 800x525 raster, expected text from
  an independent row-bitmap model, panel/border priority over the ball, frame
  entry/exit, persistent WIN frames, reset, RGB blanking, and sync alignment.
  It also writes `win_indication.ppm` in the simulation run directory.
- `tb_top_win_indication`: uses a simulated controller goal input to check WIN
  rendering, active map reads, disabled physics, regeneration masking, subsequent
  PLAY without a stale message, and the debounced centre-button return to MENU.
  This input is a visual integration stub, not a goal-detector test.

Physical WIN testing and the complete two-second replay flow remain pending the
control part. The full build can optimize away unreachable WIN logic while
`in_goal` is tied low, so validate the renderer separately with a live
`game_state` input as well as building the complete top-level design.

### Vivado 2025.2 results (2026-10-28)

- Focused visual checks: both PASS, including the 420,000-pixel raster.
- Complete regression: all 22 runs PASS, including both OLED display modes.
- Full XC7A35T bitstream: generated successfully; routed WNS +0.336 ns,
  WHS +0.052 ns, zero failing setup/hold endpoints. Resources: 2,759 LUTs,
  2,352 registers, 1.5 BRAM tiles, 6 DSPs (budget: 8).
- Separate out-of-context `render` route with `game_state` live: 100 MHz,
  2 ns input/output delays, WNS +0.575 ns and WHS +0.170 ns. The whole
  renderer uses 2 DSPs, as its existing affine row calculation does.
  This isolated check does not replace timing closure after QZ's integration.
- Physical WIN verification remains pending the control part; no board pass
  is claimed by these simulation and implementation results.
