---
story_id: 3.3
story_key: 3-3-reach-the-goal-win-and-play-again
title: Reach the goal, win, and play again
status: ready-for-dev
owner: QZ + CJX
epic: 3
depends_on:
  - 1.3
  - 1.4
  - 3.1
  - 3.2
source_epic: _bmad-output/planning-artifacts/epics.md
---

# Story 3.3: Reach the goal, win, and play again

As the player,
I want a win when the ball reaches the goal and then a new maze,
So that the game has a point and can be replayed.

## Story Context

The ball physics, wall collisions, maze generation, and the `game_ctrl` WIN
state already exist. The current integration does not complete this flow:
`My_Top_Module` ties `game_ctrl.in_goal` low, `ball_physics` does not expose a
goal result, the controller leaves WIN on its next frame tick, and VGA output
is enabled only in PLAY. This story connects goal detection to game control,
shows a visible win indication, holds it for about two seconds, and generates
another maze with the ball reset to the red start tile.

Start/goal mapping follows the 2026-10-28 team decision: the start is the red
bottom-right tile and the goal is the green top-left tile. Goal detection uses
the ball centre, as specified by AD-11; merely overlapping the green tile with
the ball's radius does not win.

## Acceptance Criteria

1. **Detect the goal at a frame-safe boundary**
   - `ball_physics` or a connected top-level detector asserts `in_goal` when
     the ball centre is inside the half-open pixel bounds of `goal_col/row`.
     Convert the signed maze-centred Q9.8 position to absolute map pixels using
     the existing 168 px map-centre offset.
   - `game_ctrl` accepts the goal only while in PLAY and at `frame_tick`, then
     enters WIN. A goal indication outside PLAY cannot trigger a win.
   - Goal detection does not alter the per-frame physics update, collision
     pipeline, restitution, gravity, speed cap, or the ball's single-writer
     rule.

2. **Show a visible win and pause**
   - While in WIN, the VGA monitor shows the current completed maze with a
     clear, high-contrast `WIN!` indication over it. Keep VGA sync timing and
     the existing menu-free VGA presentation intact.
   - Freeze ball physics and maze rotation while WIN is displayed. The win
     indication remains visible for approximately two seconds, measured as 120
     frame ticks at the nominal 60 Hz frame rate.
   - The win graphic is frame-coherent and aligned with the pipelined renderer
     output. The OLED driver and its clock/reset sequence are unchanged.

3. **Automatically replay with a fresh maze**
   - After the WIN hold interval, `game_ctrl` requests exactly one new maze
     generation, then returns to PLAY only after generation completes at the
     existing frame-safe handoff.
   - The new maze uses the existing non-debug seed-capture path. The ball is
     initialized exactly once at the new maze's red bottom-right `start_*`
     tile with zero velocity and cleared gravity fractions; it must not spawn
     on the green goal. Debug-fixed seed mode remains deterministic.
   - Preserve the active game's stage and rotation configuration across the
     automatic replay. A user reset retains its existing Story 4.2 behavior
     and returns to the menu.

4. **Verification**
   - Goal-detection coverage checks the centre inside the green goal, outside
     the goal, tile-edge boundaries, and goal coordinates across the supported
     map sizes. Radius overlap without centre entry must not trigger a win.
   - `tb_game_ctrl` verifies goal acceptance only on a PLAY frame boundary,
     WIN hold timing, one generation request after the hold, generation-done
     handoff, configuration retention, and reset behavior.
   - A top-level integration bench places or scripts the ball into the goal,
     checks the VGA win indication, then checks the new seed/map, red-start
     respawn, and return to PLAY. It also checks that physics and rotation stay
     frozen in WIN.
   - The focused Story 3.3 benches and the current-stories Vivado regression
     pass. Synthesis and routed timing/resource checks complete without
     violating the current Basys 3 timing or resource budgets.
   - A Basys 3 hardware test confirms goal detection, visible WIN indication,
     the approximate two-second pause, and automatic replay on a new maze.

## Interface and Design Notes

- Keep `game_ctrl` as the sole owner of game-state transitions. The goal signal
  is a level derived from the registered ball position and goal coordinates;
  the controller samples it at `frame_tick` only in PLAY.
- The centre point belongs to a goal tile when its absolute coordinate is
  greater than or equal to the tile's top/left edge and strictly less than its
  bottom/right edge. This handles exact boundaries without using the ball
  radius or signed-shift ambiguity.
- Count the WIN pause in `frame_tick`, not the 100 MHz system clock. Use a
  parameterized frame count defaulting to 120 so the unit bench can exercise
  short intervals while the hardware default remains about two seconds.
- Keep the completed maze visible during WIN. Add the `WIN!` pixels in a
  display path synchronized with the renderer's existing pixel latency; do not
  route OLED text into VGA or change the course-supplied OLED module.
- When WIN expires, use the existing `GENERATE` phases and seed capture. Keep
  `active_game_cfg` unchanged for this automatic replay; only a new menu start
  captures a new selection.
- Reset has priority over the WIN countdown and follows the existing menu
  reset flow. Do not require a button press to replay.

## Implementation Tasks

- [ ] Add centre-in-goal detection and connect `in_goal` from ball physics or
      the top-level detector to `game_ctrl`.
- [ ] Extend `game_ctrl` with a frame-counted WIN interval and automatic,
      single-shot regeneration after the interval.
- [ ] Add a frame-aligned VGA `WIN!` indication and enable the completed maze
      during WIN; freeze physics and rotation in that state.
- [ ] Preserve active stage/speed configuration, capture a fresh non-debug
      seed, and initialize the ball at the red start after regeneration.
- [ ] Add goal-detector, controller, and top-level Story 3.3 benches; include
      them in the focused and current-stories Vivado runners.
- [ ] Run the Vivado regression plus synthesis/routed timing and resource
      checks; record the exact results below.
- [ ] Perform the Basys 3 win-and-replay test and record the result in the PR
      and this artifact.

## Prerequisite Check

- Story 1.3 maze generation is present and provides `goal_*`, `start_*`, and
  fresh-seed capture for non-debug runs.
- Story 1.4 `game_ctrl` provides the MENU, GENERATE, PLAY, and WIN states,
  generation handoff, and the Epic 4 reset-to-menu integration.
- Story 3.1 ball physics and Story 3.2 wall collisions are implemented; the
  Story 3.2 artifact records successful simulation, routed timing, and board
  checks. The missing Story 3.3 connection is goal detection and replay.
- The current gap is visible in `rtl/My_Top_Module.v` (`in_goal` tied low) and
  `rtl/game_ctrl.v` (WIN exits at the next frame tick); `ball_physics` has no
  goal output yet.

## Definition of Done

- The ball centre reaching the green goal enters WIN on a frame boundary.
- The VGA monitor shows `WIN!` over the frozen maze for about two seconds.
- A fresh maze is then generated and play resumes with the ball on its red
  bottom-right start tile and the active game configuration preserved.
- Story 3.3 and current-stories Vivado regressions pass, routed timing and
  resource checks meet the project budgets, and the Basys 3 behavior is
  checked.
- The feature is reviewed and merged by pull request.

## Implementation Evidence

Not implemented yet. This artifact is ready for development; add simulation,
Vivado, and board evidence as Story 3.3 is built and reviewed.
