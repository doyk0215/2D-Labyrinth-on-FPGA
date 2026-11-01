---
story_id: 7.4
story_key: 7-4-add-n15-stage
title: Add the N = 15 stage
status: review
owner: CJX
epic: 7
depends_on: [7.1, 7.3]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/56
---

# Story 7.4: Add the N = 15 stage

HUGE is now the third OLED menu entry. This branch starts independently from
main `86f5158`, after the map/camera/renderer stories merged; it does not
include the independent Story 8.2 countdown branch.

## Implementation

- `menu_ctrl.selected_stage` grows from one to two bits: 0 EASY, 1 HARD,
  2 HUGE. DOWN advances and UP reverses with wrap; simultaneous UP/DOWN
  keeps the selection. Reset and return-to-menu select EASY as before.
- The three stage entries use rows 1..3. Row 0 retains the LEFT/settings and
  CENTER/start hints. The settings page, speed cycling and retention remain.
- HUGE packs N=15 with restitution 1 (the existing HARD bounce preset).
  No new restitution policy is specified by this story; reusing HARD keeps
  the choice explicit. The existing 8-bit game_cfg packing is unchanged.
- The existing controller latches the chosen configuration on start; menu
  inputs during generation or play cannot alter the active maze size.
- `oled_status_text` labels N=15 as STAGE 3 HUGE in PLAY, WIN and GENERATE.
  Time uses the same existing BCD inputs as the other stages. On this branch
  alone it remains the main branch's count-up; Story 8.2 changes that to a
  countdown when the branches are integrated.
- The existing N=15 generator, goal detector, physics, camera and renderer
  need no RTL changes. Their prior stories supply the larger map/view.

## Simulation

From this checkout in Vivado 2025.2:

```tcl
set repo [pwd]
source [file join $repo tb run_story74.tcl]
source [file join $repo tb run_current_stories.tcl]
```

- Extended menu bench checks all three selections and both wrap directions,
  simultaneous inputs, configuration packing, settings speed cycles,
  retention, start pulse, reset and no navigation outside MENU.
- Status formatter checks HUGE in PLAY/WIN, its distinct name and BCD time.
- New real-top integration uses the debounced physical inputs to select and
  confirm HUGE, checks active configuration despite later menu inputs, real
  N=15 generation, bottom-right (29,29) spawn, top-left (1,1) goal and snapped
  camera. An independent tile-level BFS through the actual generated RAM
  proves start-to-goal reachability on both initial generation and replay.
- The real OLED mailbox transfers the complete HUGE status to its frame
  buffer. Moving only the ball to the goal exercises the actual physics goal
  detector, frame-safe WIN, hold and automatic N=15 replay. CENTER returns
  to EASY menu. This does not claim a physical play-through.

## Validation

Vivado 2025.2 on 2026-11-01, full `My_Top_Module`, Basys 3
`xc7a35tcpg236-1`:

- Focused `run_story74.tcl`: menu, formatter and real-top integration PASS.
- Fresh synthesis, implementation and bitstream generation PASS, with no
  errors or critical warnings. Bitstream DRC: 0 errors.
- Routed WNS **+0.780 ns**, WHS **+0.122 ns**, TNS/THS **0.000 ns**;
  all user-specified timing constraints met.
- Resources: **3,525 LUTs** (16.95%), **3,715 registers** (8.93%),
  **2.5 BRAM tiles**, **6 DSPs**, **0 MMCM / 0 PLL**, within AD-8.
- Build reports: `C:/EE2026Projects/build-story74-86f5158/timing_summary.rpt`
  and `utilization.rpt`. Generated files stay outside version control.
- Full regression: results recorded after completion.

## Review and board check

QZ reviews the former menu implementation and DY reviews OLED/status and the
camera/render integration. QZ or DY must perform the non-author board check
under `docs/parallel-workstreams.md` section 7.3 and record tested commit,
PASS/FAIL and a photo or note. Hardware PASS is pending.

1. Program `C:/EE2026Projects/build-story74-86f5158/labyrinth.runs/impl_1/My_Top_Module.bit`.
2. Check all three menu rows, UP/DOWN wrap and settings/back/start controls.
3. Select HUGE: verify bottom-right spawn, camera follow without shaking,
   readable walls and a reachable top-left goal. OLED identifies STAGE 3 HUGE
   and shows the running time. Win, check replay stays HUGE, then CENTER back.
4. Recheck EASY/HARD and the retained rotation-speed preference. This bitstream
   does not contain Story 8.2; countdown behavior is tested separately there.
