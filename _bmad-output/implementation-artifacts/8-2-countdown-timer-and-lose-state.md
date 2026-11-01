---
story_id: 8.2
story_key: 8-2-countdown-timer-and-lose-state
title: Countdown timer and LOSE state
status: review
owner: CJX
epic: 8
depends_on: [6.1]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/59
---

# Story 8.2: Countdown timer and LOSE state

Every new maze loads its stage limit: EASY 60 s, HARD 120 s, HUGE/N=15 180 s.
The limits and LOSE hold are parameters. Counting uses the 100 MHz system
clock, independently of the VGA frame frequency; PLAY is the only counting
state. Reset clears the display, and `phys_init` loads a fresh limit and
clears the fractional second. WIN and LOSE freeze the remaining time.

## Implementation and interface

- `game_timer` adds `n_cells` and `time_up`. Its legacy `elapsed_*_bcd` output
  names now mean **time left**, including on the existing OLED and WIN panel.
  Limits are clamped to 0..5999 seconds and converted to BCD at elaboration,
  so the synthesized datapath has no divider. Zero saturates without wrap.
- `game_ctrl` accepts `time_up` at a frame boundary, with priority over goal
  and regeneration, enters shared `ST_LOSE`, holds `LOSE_HOLD_FRAMES`
  (default 120, approximately two seconds), then returns to MENU without
  replay. A goal strictly before expiry retains the existing WIN replay.
- `time_up` includes the terminal clock edge (00:01 -> 00:00), preventing
  a goal coincident with the deadline from producing a zero-time WIN.
- The top disables rotation commands and discards snap gestures in LOSE;
  physics already runs only in PLAY. CENTER short/full reset works in LOSE.
- Story 8.3 is responsible for the TIME UP OLED/monitor page. The current
  display masking/formatter is retained here. HUGE becomes menu-selectable
  in independent Story 7.4; its timer limit is already supported here.
- The interface contract is updated in `docs/parallel-workstreams.md`.
  No state code, configuration width, supplied OLED or PS/2 source changes.

## Simulation

From the repo root in Vivado 2025.2:

```tcl
set repo [pwd]
source [file join $repo tb run_story82.tcl]
source [file join $repo tb run_current_stories.tcl]
```

- Timer: exact full-second cadence; default 60/120/180-second limits; no
  reload on a mid-game stage change; PLAY-only countdown; discarded partial
  second on pause; WIN/LOSE/MENU freeze; new-maze reload and reset; terminal
  expiry edge; zero saturation. CLK_HZ=1 exercises every BCD transition from
  99:59 through zero and the minimum counter width; negative/over-cap limits
  are clamped. Expected values come from an independent integer-seconds model.
- New real-top integration: actual menu/generator/physics, natural timeout,
  frame-only state changes, exact LOSE hold, held/released smooth and snap
  buttons, frozen ball position/velocity, WIN freeze/replay reload, timeout
  versus goal/regeneration (including exact clock coincidence), short reset,
  long reset and no stage start after long release. Only the frame interval
  and configured seconds are shortened; the deadline test uses the real timer.
- Story 4.4 timer/status integration and Story 6.1 state-width fixtures are
  updated from elapsed-time assumptions to countdown semantics. Existing
  v1 controller scenarios tie the new timeout input low.

## Validation

Vivado 2025.2 on 2026-11-01, full `My_Top_Module`, Basys 3
`xc7a35tcpg236-1`:

- Focused `run_story82.tcl`: both benches PASS, including exact-deadline goal.
- Fresh synthesis, routing and bitstream generation PASS; no errors or critical
  warnings. Bitstream DRC: 0 errors. The ordinary implementation warning is
  the existing reset-activity power-estimation warning, not a timing failure.
- Routed WNS **+0.195 ns**, WHS **+0.019 ns**, TNS/THS **0.000 ns**;
  all user-specified timing constraints met.
- Resources: **3,529 LUTs** (16.97%), **3,688 registers** (8.87%),
  **2.5 BRAM tiles**, **6 DSPs**, **0 MMCM / 0 PLL**, within AD-8.
- Reports: `C:/EE2026Projects/build-story82-86f5158/timing_summary.rpt`
  and `utilization.rpt`. Build uses an isolated copy of this branch's RTL.
- Full regression: results recorded after completion.

## Review and board check

QZ reviews the prior controller/timer interface, and DY reviews top integration
and shared header documentation. Under `docs/parallel-workstreams.md` section
7.3, QZ or DY must run the non-author board check and record tested commit,
PASS/FAIL and a photo or note on the PR. CJX has not claimed a board PASS.

1. Program `C:/EE2026Projects/build-story82-86f5158/labyrinth.runs/impl_1/My_Top_Module.bit`.
2. EASY starts at 01:00, HARD at 02:00. Compare the countdown to a watch;
   holding rotation must not alter its rate. Generation consumes no time.
3. Let a game expire: the ball and both smooth/snap rotation stop, then the
   menu returns after approximately two seconds. TIME UP graphics arrive in
   Story 8.3; this build intentionally uses the existing display behavior.
4. Win before timeout: remaining time freezes on OLED and VGA, then replay
   loads the full stage limit. Check CENTER short and long reset during LOSE.
5. N=15/03:00 can be checked after Story 7.4 integration, or using the legacy
   debug configuration; do not claim it was menu-tested on this branch alone.
