---
story_id: 3.3
story_key: 3-3-reach-the-goal-win-and-play-again
title: Reach the goal, win, and play again
status: review
owner: QZ + CJX
epic: 3
depends_on:
  - 1.3
  - 1.4
  - 3.1
  - 3.2
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/22
---

# Story 3.3: Reach the goal, win, and play again

As the player,
I want a win when the ball reaches the goal and then a new maze,
So that the game has a point and can be replayed.

The start is the red bottom-right cell, and the goal is the green top-left
cell. The ball spawns on `start_*`.

## Current Implementation Boundary

PR #47 supplies CJX's VGA win-indication work: the renderer snapshots WIN at a
frame boundary, displays a fixed-screen `YOU WIN` panel and green outline over
the maze and ball, and has pixel-level and top-level visual benches. That work
consumes the existing `game_state == WIN`; it does not detect the goal or hold
WIN for the replay interval.

This branch completes QZ's control portion: detect the ball centre in the goal
tile, connect `in_goal` to `game_ctrl`, hold WIN for about two seconds, then
generate a fresh maze and initialize the ball at the red start. Preserve the
PR #47 render/game-state interface and tests.

## Acceptance Criteria

1. **Detect the goal at a frame-safe boundary**
   - Assert `in_goal` when the ball centre is inside the half-open bounds of
     `goal_col/row`, using the existing maze-centred Q9.8 position and 168 px
     map-centre offset. Merely overlapping the green tile with the ball radius
     does not win.
   - `game_ctrl` accepts the goal only while in PLAY and at `frame_tick`, then
     enters WIN. An `in_goal` level outside PLAY cannot trigger a win.
   - Goal detection does not change physics update cadence, collision behavior,
     restitution, gravity, speed cap, or the single-writer rule for ball state.

2. **Show the teammate's win indication and pause**
   - Keep PR #47's frame-synchronous `YOU WIN` panel and green outline over the
     completed maze. Preserve VGA sync timing and the existing menu-free VGA
     presentation; leave OLED driver behavior unchanged.
   - Freeze physics and maze rotation while WIN is displayed. Hold WIN for
     approximately two seconds, measured as 120 VGA frame ticks at nominal
     60 Hz. The WIN indication remains visible throughout the hold.

3. **Automatically replay with a fresh maze**
   - After the WIN hold, request exactly one new maze generation and return to
     PLAY only after the existing frame-safe generation handoff.
   - In non-debug mode, capture a fresh seed. Initialize the ball exactly once
     at the new maze's red bottom-right `start_*` tile with zero velocity and
     cleared gravity fractions; do not spawn on the green goal. Debug-fixed
     seed mode remains deterministic.
   - Preserve the active game's stage and rotation configuration during
     automatic replay. A user reset keeps its existing behavior and returns
     to the menu.

4. **Verification**
   - Goal-detection coverage checks the goal centre, points outside the goal,
     half-open tile-edge boundaries, and supported maze sizes. Radius overlap
     without centre entry must not trigger a win.
   - `tb_game_ctrl` checks PLAY-only frame-boundary acceptance, the configured
     WIN frame count, exactly one generation request, generation-done handoff,
     retained active configuration, and reset behavior.
   - A top-level control integration bench exercises the connected ball goal
     detector through WIN, the complete pause, fresh-seed generation, red-start
     respawn, and return to PLAY. It checks that physics and rotation remain
     frozen in WIN and that PR #47's panel is visible for the hold interval.
   - Run the focused Story 3.3 tests and current-stories Vivado regression.
     Run synthesis and routed timing/resource checks without generating a
     bitstream; record the measured results.
   - Hardware check on Basys 3 confirms goal detection, the visible WIN panel,
     the approximate two-second pause, and automatic replay.

## Interface and Design Notes

- `game_ctrl` remains the sole owner of state transitions. `in_goal` is a level
  derived from the registered ball position and goal coordinates; sample it
  on `frame_tick` only in PLAY.
- Goal bounds are half-open: coordinate greater than or equal to the tile's
  left/top edge and strictly less than its right/bottom edge. Compare in the
  existing signed Q9.8 maze frame to avoid signed-shift ambiguity.
- Count the pause in `frame_tick`, not the 100 MHz system clock. Default to
  120 frames and provide a parameter so the controller bench can use a short
  interval.
- Keep PR #47's `game_state` input to `render`, `win_overlay`, and its frame
  snapshot logic unchanged. Its WIN panel is fixed in screen space and has
  already been checked against renderer pixel latency.
- Reuse the current `GENERATE` seed-capture phases after WIN. Do not rewrite
  `active_game_cfg`; a new menu start is the only operation that captures a
  different selection.
- Reset has priority over the WIN countdown and uses the existing reset-to-menu
  path. No button press is required to replay.

## Implementation Tasks

- [x] Connect `game_state` to the renderer and display the frame-synchronous
      `YOU WIN` indication over the completed maze during WIN (CJX, PR #47).
- [x] Add pixel-level and top-level visual benches for the win indication
      (CJX, PR #47).
- [x] Detect ball-centre entry into the goal tile and connect `in_goal` to
      `game_ctrl`.
- [x] Extend `game_ctrl` with a frame-counted WIN interval and exactly one
      automatic regeneration request after the interval.
- [x] Preserve active configuration, capture a fresh non-debug seed, respawn
      at the red start, and freeze physics/rotation during WIN.
- [x] Add goal-detector, controller timing, and full top-level control benches;
      include them in the focused and current-stories Vivado runners.
- [x] Run current-stories regression and routed timing/resource checks; record
      exact results.
- [ ] Perform the Basys 3 goal-to-replay test and record it in the PR and here.

## Prerequisite Check

- Story 1.3 maze generation provides `start_*`, `goal_*`, and the non-debug
  seed-capture path.
- Story 1.4 `game_ctrl` provides MENU, GENERATE, PLAY, and WIN plus the
  generation handoff and reset-to-menu integration.
- Stories 3.1 and 3.2 supply ball physics and wall collisions. Their current
  code and Story 3.2 verification evidence are present in the fetched branch.
- The remaining control gaps before this work were `in_goal` tied low in
  `My_Top_Module`, no goal output from `ball_physics`, and `game_ctrl` leaving
  WIN at its next frame tick.

## PR #47 Visual Verification (reported by its author)

- `tb_win_render` checks the `YOU WIN` glyph and panel across all 420,000
  positions of an 800×525 raster, including frame entry/exit, reset, priority,
  blanking, and sync alignment.
- `tb_top_win_indication` checks visual integration using a forced controller
  goal input. It does not verify goal detection or the two-second replay flow.
- PR #47 reports the focused visual benches and a 22-run current-stories
  regression passing. It also reports routed WNS +0.336 ns and WHS +0.052 ns.
  These are the teammate's results; rerun the regression and routed check after
  the control integration.
- The board test and complete control path remain pending.

## Definition of Done

- The ball centre reaching the green goal enters WIN on a frame boundary.
- The `YOU WIN` VGA panel remains over the frozen maze for about two seconds.
- A fresh maze is then generated and play resumes with the ball on its red
  bottom-right start tile and the active configuration preserved.
- Focused and full Vivado regressions pass, routed timing/resources meet the
  project budgets, and the Basys 3 behavior is checked.
- The feature is reviewed and merged by pull request.

## Implementation Evidence

- Control integration detects the ball centre in the half-open goal tile,
  enters WIN only on a PLAY frame boundary, holds WIN for 120 frame ticks by
  default, then captures a new non-debug seed and regenerates once. The active
  configuration is retained, and the ball is initialized at the new red start.
- The top-level integration bench checks goal detection, a shortened three-frame
  WIN interval, persistent visual state, frozen physics and rotation, a changed
  seed/map, configuration retention, and red-start respawn. Goal-boundary
  coverage checks every supported generated goal coordinate for N=2..10.
- Vivado 2025.2 focused Story 3.3 suite passed, including both PR #47 visual
  benches and the new controller/goal integration. The full current-stories
  regression also passed, including both OLED modes.
- Vivado synthesis and routing completed on `My_Top_Module` without a bitstream.
  Routed timing: WNS 0.743 ns and WHS 0.086 ns, with zero failing setup/hold
  endpoints; all specified timing constraints are met. Utilization: 2809 Slice
  LUTs (13.50%), 2359 Slice Registers (5.67%), 1.5 Block RAM tiles, and 6 DSPs.
  DRC reports zero errors and 11 DSP pipelining advisories.
- The Basys 3 win-and-replay hardware check remains pending; no board pass is
  claimed.
