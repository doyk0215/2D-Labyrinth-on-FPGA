---
story_id: 6.2
story_key: 6-2-long-press-btnc-full-reset
title: Long-press BTNC full reset
status: review
owner: CJX
epic: 6
depends_on: []
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/52
---

# Story 6.2: Long-press BTNC full reset

Hold CENTER for about two seconds to recover the game and its peripherals
without reprogramming the Basys 3. A short press confirms or returns to the
menu only when released; a long press never also confirms a stage.

## Implementation

- New `rtl/centre_button.v` synchronizes and debounces both edges. It counts
  a continuous debounced hold, saturates on long reset, and re-arms only on
  release. It is independent of the reset it generates. The top-level
  `LONG_PRESS_CYCLES` parameter defaults to 200,000,000 clocks at 100 MHz.
- `My_Top_Module` distinguishes power-on/full reset (`system_reset`) from
  the existing short gameplay reset (`rst`). Full reset restores EASY/NORMAL
  menu defaults and clears the game, angle, physics, generator, elapsed timer,
  seed, input filters, mouse, OLED text mailbox, and OLED startup path.
- `game_ctrl.full_reset` selects MENU even for the legacy auto-start debug
  option. The existing `rst` behavior and automatic WIN replay stay intact.
- Short release still exits settings, starts the selected stage from MENU,
  or returns from GENERATE/PLAY/WIN to MENU. It retains the existing menu
  rotation preference and does not restart OLED power sequencing.
- OLED reset uses asynchronous assertion and two-stage release in its own
  clock domain. Its divider keeps running. The supplied PS/2 VHDL and
  `Oled_Display.v` are unchanged. Maze RAM need not be cleared in MENU: display
  reads are disabled and the generator rewrites the map before the next PLAY.
- `docs/parallel-workstreams.md` records the new reset signals and controller
  input. This branch starts independently from `main` at `5f89f1b`; Story 6.1
  remains in its separate PR and must retain its shared state names/widths
  when the branches are integrated.

## Simulation

From the repo root, in Vivado 2025.2:

```tcl
set repo [pwd]
source [file join $repo tb run_story62.tcl]
source [file join $repo tb run_current_stories.tcl]
```

- `tb_centre_button`: contact bounce, separate short holds, action only on
  release, long threshold, held-reset saturation, no short after long, re-arm,
  button held through power-on, and minimum counter parameters.
- `tb_top_story62_reset`: real controller/menu/generator/physics/timer, PS/2
  mouse, and OLED integration. Long reset from MENU (nondefault settings),
  GENERATE, PLAY, and WIN restores defaults and MENU; holding/releasing never
  starts a stage. Checks actual OLED reset-pin and initialization-command
  phases repeat and fresh menu text crosses the mailbox. Also checks short
  confirm/return, normal play after repeated resets, and the legacy debug
  controller's forced MENU recovery.
- Only the new integration bench scales the OLED `ClkFreq` delay/frame
  counters to 62,500 for simulation speed. The separate existing OLED display
  tests retain nominal 6.25 MHz timing and test both display modes.

Vivado 2025.2 validation on 2026-10-31:

- Focused `run_story62.tcl`: both benches PASS. The final focused run also
  checks short return from GENERATE/WIN, retention of a FAST preference on
  short return, and clearing a nonzero rotation angle on full reset.
- Full `run_current_stories.tcl` regression: **29/29 simulation runs PASS**
  (27 core benches plus both OLED display modes). Existing v1 assertions and
  scenarios are unchanged; the controller unit bench ties the new input low.
- Fresh full-top Basys 3 build (`xc7a35tcpg236-1`) through synthesis, routing,
  and bitstream generation: PASS. No errors or critical warnings in synthesis
  or implementation; bitstream DRC reports 0 errors.
- Final routed WNS **+0.578 ns**, WHS **+0.094 ns**, TNS/THS **0.000 ns**;
  all user-specified timing constraints met.
- Routed resources: **2,924 LUTs**, **2,606 registers**, **1.5 BRAM tiles**,
  **6 DSPs** (within the project's 8-DSP budget).
- Local build/report directory: `C:/EE2026Projects/maze_story62_5f89f1b`.
  Bitstream: `labyrinth.runs/impl_1/My_Top_Module.bit`. Generated build
  outputs remain outside version control.
- `git diff --check`: PASS.

## Review and board check

QZ reviews the controller/input changes as previous stream B owner. DY
reviews the top-level/OLED reset integration as current top-level owner and
previous OLED owner. The reset interface contract needs their agreement.

Per `docs/parallel-workstreams.md` section 7.3, someone other than CJX must run
the board check and record PASS/FAIL, branch/commit, and a photo or note on
the PR. Hardware verification remains pending.

Board checklist for `feature/6-2-long-press-reset`:

1. Recreate/build the project from this branch's sources (including the new
   `centre_button.v`) using `scripts/create_project.tcl`, or program the fresh
   Story 6.2 bitstream. Connect Basys 3, VGA, Pmod OLED, and the mouse.
2. Select HARD and a nondefault rotation speed. Hold CENTER for over two
   seconds from the menu/settings page. No stage starts while held or when
   released; defaults return to EASY/NORMAL. OLED restarts and shows the menu.
3. Short-press/release CENTER to start. Verify rotation, ball movement, and
   the elapsed timer. Short-press/release to return to MENU; normal settings
   behavior remains intact.
4. Repeat the long hold during GENERATE, PLAY, and the WIN pause. Each must
   recover to a fresh MENU with cleared game/timer state, restored settings,
   restarted mouse/OLED, and no unintended start. GENERATE is brief; if it
   finishes before the hold threshold, record that the hold crossed into PLAY
   (the simulator separately verifies reset while still in GENERATE).
5. Keep CENTER held for several seconds after reset. It must stay in MENU.
   Release it, then make a new short press to start; mouse and OLED must work
   again. Record the result and identify the tested commit on the PR.
