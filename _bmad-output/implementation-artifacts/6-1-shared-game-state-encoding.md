---
story_id: 6.1
story_key: 6-1-shared-game-state-encoding
title: Shared game-state encoding
status: review
owner: CJX
epic: 6
depends_on: []
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/51
---

# Story 6.1: Shared game-state encoding

The v1 MENU/GENERATE/PLAY/WIN codes occupy every value of a 2-bit state bus.
Story 8.2 needs a distinct LOSE code. This change extends the shared state
contract before the countdown feature starts, preserving the existing flow.

## Implementation

- `rtl/labyrinth_pkg.vh` defines `GAME_STATE_W=3` and the shared `ST_MENU=0`,
  `ST_GENERATE=1`, `ST_PLAY=2`, `ST_WIN=3`, and `ST_LOSE=4` macros.
- `game_ctrl`, `My_Top_Module`, `render`, `game_timer`, and `oled_status_text`
  use that width and those named codes. Existing benches use the same contract.
- LOSE is reserved only. The controller still follows MENU -> GENERATE -> PLAY
  -> WIN -> GENERATE, with the existing reset/regenerate paths and WIN pause.
  Elapsed time still counts up in PLAY and freezes in WIN.
- `game_cfg` and `active_game_cfg` remain 8 bits with their existing packing.
- `docs/parallel-workstreams.md` records the updated state interface.

## Verification

Run from the repo root with Vivado 2025.2:

```tcl
set repo [pwd]
source [file join $repo tb run_story61.tcl]
source [file join $repo tb run_current_stories.tcl]
```

`tb_game_state_encoding` checks the preserved v1 flow, all eight configuration
bits (using `8'ha5`), and reserved codes 4 through 7 at the actual top-level
consumer ports. It also checks that those codes do not alias MENU, PLAY, or
WIN, that the timer stays stopped, and that valid WIN rendering/status remain
available. The existing controller recovery path is checked for an unused code.

Vivado 2025.2 validation on 2026-10-31, based on `main` at `5f89f1b`:

- Focused `run_story61.tcl`: PASS, including the reserved-code checks above.
- Full `run_current_stories.tcl` regression: **28/28 simulation runs PASS**
  (26 core benches plus OLED test-pattern and text modes). Existing v1
  assertions and scenarios are preserved; only state names/widths migrated.
- Fresh Basys 3 build of `My_Top_Module` (`xc7a35tcpg236-1`), through
  synthesis, routing, and `write_bitstream`: PASS. No synthesis or
  implementation errors or critical warnings; bitstream DRC reports 0 errors.
- Final routed WNS **+0.612 ns**, WHS **+0.094 ns**, TNS/THS **0.000 ns**;
  all user-specified timing constraints met.
- Routed utilization: **2,916 LUTs**, **2,577 registers**, **1.5 BRAM tiles**,
  **6 DSPs** (within the 8-DSP project budget).
- Build/report directory: `C:/EE2026Projects/maze_story61_5f89f1b`.
  Bitstream: `labyrinth.runs/impl_1/My_Top_Module.bit`. Generated Vivado
  projects, logs, reports, and bitstreams remain outside version control.
- `git diff --check`: PASS.

## Required review and board check

- QZ reviews the controller/timer/status changes as their previous owner.
- DY reviews the top-level/render changes as their current owner. The shared
  package and interface extension need agreement from CJX, QZ, and DY.
- QZ or DY must perform and record the board check on the PR, per section 7.3
  of `docs/parallel-workstreams.md`; CJX is the author and cannot supply it.

Board checklist for branch `feature/6-1-shared-game-state`:

1. Build/program `My_Top_Module` for Basys 3 with the branch sources and XDC.
   Connect the VGA display, Pmod OLED, and mouse. Power-up shows the existing
   OLED stage menu; VGA remains masked until a game starts.
2. Use UP/DOWN to select EASY/HARD. Open settings with LEFT, change rotation
   speed with UP/DOWN, and return with CENTER. Confirm with CENTER to start.
   Check stage/size and rotation settings are retained.
3. Check generation finishes, the maze and ball appear, rotation works, and
   the OLED elapsed timer advances in PLAY. Exercise smooth and SW5 snap modes.
4. Press DOWN in PLAY to regenerate. Verify a fresh maze and cleared timer.
   Press CENTER to return to the menu and start again.
5. Reach the green goal: VGA and OLED show the existing WIN indication, the
   ball/rotation and timer freeze, then the roughly two-second pause ends with
   automatic replay and a cleared timer.
6. Record PASS/FAIL, story 6.1, branch/commit, and a photo or note on the PR.
   No LOSE/countdown screen is expected in this story.

Implementation is ready for review only after simulation and timing pass;
merge approval still requires the non-author board PASS and interface reviews.
