---
story_id: 3.4
story_key: 3-4-reset-and-frame-budget-check
title: Reset and frame-budget check
status: review
owner: QZ
epic: 3
depends_on:
  - 1.4
  - 3.1
  - 3.2
  - 3.3
  - 4.2
  - 4.3
  - 4.4
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/23
---

# Story 3.4: Reset and frame-budget check

As the examiner,
I want a reset that always gives a clean new game and a game that never
stutters,
So that a demo can be recovered and runs smoothly.

## Story Context

Stories 1.4 and 3.1–3.3 provide the game controller, ball physics, collisions,
and goal/replay flow. Epic 4 adds the OLED menu and elapsed timer. The top-level
already routes a debounced BTNC press from active play to the menu; the shared
reset pulse reaches `game_ctrl`, `maze_gen`, the angle accumulator, ball
physics, and timer. `menu_ctrl` receives a return-to-menu pulse so it can reset
the stage page while retaining the Story 4.3 rotation-rate choice. This story
adds integration checks for a clean reset from every active state, a fresh
maze after confirmation, and physics finishing within vertical blanking. It
also requires the multi-minute Basys 3 observation.

Because the menu is now part of the game, reset from GENERATE, PLAY, or WIN
returns to MENU. It clears active-game state immediately; the next menu
confirmation starts exactly one fresh generation, and PLAY waits for the
existing frame-safe generation handoff. Once in MENU, BTNC retains its Story
4.2 confirm/start behavior. Preserve Story 4.3's selected rotation-rate
setting across an in-game reset, and retain Story 4.2's initial stage-menu
behavior.

## Acceptance Criteria

1. **Reset from every game state**
   - A debounced BTNC press in GENERATE, PLAY, or WIN returns the controller
     to MENU and clears the current ball position, velocity, gravity
     fractions, maze angle, pending snap-rotation state, and elapsed timer.
   - Reset has priority over generation completion, a frame update, and the
     WIN countdown. It cancels stale start, generation, and replay handoffs;
     no `phys_init` or `gen_start` from the interrupted game may take effect
     after reset.
   - After reset returns to MENU, BTNC uses the normal menu confirm behavior.
     Keep the Story 4.2 initial stage selection and the Story 4.3 rotation-rate
     retention behavior.

2. **Start cleanly after reset**
   - The next menu confirmation captures the selected game configuration and
     requests exactly one fresh maze generation with the normal seed policy.
   - The controller stays out of PLAY until the new generation has completed
     and the existing frame-safe handoff occurs. The ball is initialized
     exactly once at the new red start tile, with zero velocity and cleared
     gravity fractions; the angle and timer begin at zero.
   - Reset from WIN cancels automatic replay. Reset from GENERATE cancels the
     in-flight generation before the next menu start; no stale `gen_done`
     pulse may launch the prior game.

3. **Measure the physics frame budget**
   - Measure from `frame_tick` to `phys_done` in simulation across supported
     maze sizes and representative free-flight and wall-collision cases.
   - Every measured physics update completes before active video resumes. At
     the current 100 MHz system clock and 25 MHz pixel enable, the vertical
     blanking budget is 45 × 800 × 4 = 144,000 system-clock cycles.
   - Record the worst observed cycle count, remaining margin, test coverage,
     and Vivado version in the implementation evidence. Explain any
     assumptions about collision workload and maze seeds.

4. **Keep the displayed game stable**
   - Run the current-stories Vivado regression and the Story 3.4 focused
     benches. The reset checks cover MENU, GENERATE, PLAY, and WIN, including
     simultaneous reset and completion events, one fresh generation after
     confirmation, and clean respawn.
   - Run Vivado 2025.2 synthesis and routed timing/resource checks without
     generating a bitstream; report setup/hold results and resource use.
   - On Basys 3, play for several minutes and observe no visible tearing or
     stutter. Test BTNC reset from active play and confirm the OLED returns to
     MENU; start again and confirm a clean new game. Record the physical
     result in the PR and this artifact.

## Interface and Design Notes

- `My_Top_Module` currently makes `rst` the OR of power-on reset and the
  debounced in-game reset request. `game_ctrl` also receives
  `return_to_menu`; preserve the distinction between power-on initialization
  and an in-game return so menu settings follow Stories 4.2 and 4.3.
- `angle_accumulator`, `ball_physics`, and `game_timer` consume the game reset
  pulse. Verify their visible state and internal pending/fractional state are
  cleared, rather than checking only the controller state.
- `game_ctrl` owns generation and `phys_init`. Keep its single-writer and
  frame-safe handoff rules; reset must dominate `gen_done`, `frame_tick`, and
  the WIN frame counter.
- Current VGA timing is 800 × 525 with 480 active rows and a 1-in-4 pixel
  enable. The blank interval starts at `frame_tick` and lasts 45 lines, or
  144,000 clocks at 100 MHz. If timing parameters change, calculate the budget
  from the configured totals and report the revised value.
- `ball_physics.phys_done` marks completion of its sequential per-frame
  collision update. Instrument it in the testbench; do not add debug counters
  or change the physics cadence solely to obtain a measurement.
- Keep the established simplification explicit in the report: gravity always
  points down on screen and is transformed into maze coordinates; no
  centrifugal, Coriolis, or moving-wall forces are modeled.

## Implementation Tasks

- [x] Audit top-level and controller reset priority
      across MENU, GENERATE, PLAY, and WIN.
- [x] Add reset coverage for interrupted generation, pending frame handoff,
      active physics, pending snap rotation, timer state, and WIN replay.
- [x] Verify that the next confirmed start generates one fresh maze and
      respawns the ball at its red start tile with zeroed dynamics.
- [x] Add a physics frame-budget bench covering supported maze sizes and
      representative collision cases; record worst latency against 144,000
      system-clock cycles.
- [x] Run the focused Story 3.4 and current-stories Vivado 2025.2 suites.
- [x] Run synthesis and routed timing/resource checks without a bitstream.
- [ ] Complete the multi-minute Basys 3 no-stutter and reset/restart check;
      record the result in the PR and this artifact.

## Prerequisite Check

- Story 1.4 controller and reset-to-menu path are present on `main`.
- Stories 3.1 and 3.2 physics/collision implementation and verification are
  present on `main`.
- Story 3.3 control and VGA win indication are merged in PR #47. Its Basys 3
  goal-to-replay check remains pending in the tracker.
- Stories 4.2 and 4.3 provide the menu, reset behavior, and rotation setting.
  Story 4.3's physical check remains pending.
- Story 4.4 is merged in PR #48 at merge commit `965dfd9`; its timer clears on
  reset and new-maze initialization. Its physical check remains pending.
- The source acceptance criteria are in issue #23 and the Story 3.4 section of
  `_bmad-output/planning-artifacts/epics.md`.

## Definition of Done

- Reset returns the game to MENU with no stale ball, angle, timer, generation,
  or replay state. The next confirmation generates one fresh maze and starts
  cleanly at its red start tile.
- Every physics step completes within the measured vertical-blank budget,
  with the maximum observed latency and margin recorded.
- Focused and current-stories Vivado regressions pass; synthesis and routed
  timing/resource results are documented.
- The multi-minute Basys 3 play check shows no tearing or stutter, and reset
  and restart work on hardware.
- The feature is reviewed and merged by pull request.

## Implementation Evidence

- The existing shared game-reset pulse reaches `game_ctrl`, `maze_gen`,
  `angle_accumulator`, `ball_physics`, and `game_timer`. The integration bench
  verifies reset from GENERATE, PLAY, and WIN; aborts in-flight generation;
  checks that WIN replay is canceled; and confirms a subsequent menu start
  captures a fresh seed, generates once, and respawns at the red start. It
  checks timer, angle and snap phase, ball position/velocity/gravity fractions,
  menu text, and retention of the FAST rotation setting.
- Vivado 2025.2 focused Story 3.4 controller-priority, snap-reset,
  top-integration, and frame-budget benches passed. Reset coverage includes
  simultaneous reset with frame tick, generation completion and goal events;
  interrupted generation; runtime physics/angle/timer state; and canceling
  WIN replay.
- The frame-budget bench covered 36 generated mazes (N=2..10, two seeds,
  vertical and horizontal outward gravity), for 1,728 measured physics frames
  including free flight and outer-wall collisions. Worst
  `frame_tick`-to-`phys_done` latency was 13 system clocks against the
  144,000-clock blanking budget, leaving 143,987 clocks of margin.
- The current-stories Vivado 2025.2 regression passed, including both OLED
  display modes, the top-level ball bench, and the Story 3.4 benches.
- Vivado 2025.2 synthesis completed with zero errors and zero critical
  warnings. Routed timing has WNS +0.227 ns and WHS +0.055 ns, with zero setup
  or hold failing endpoints; all specified timing constraints are met.
  Utilization is 2,911 Slice LUTs (14.00%), 2,576 Slice Registers (6.19%),
  1.5 Block RAM tiles, and 6 DSPs. DRC reports zero errors and 11 DSP
  pipelining advisories (9 input-pipeline and 2 output-pipeline warnings).
- The routed check stopped before bitstream generation. No bitstream has been
  generated.
- The multi-minute Basys 3 play, reset, and restart observation remains
  pending; no hardware pass is claimed.
