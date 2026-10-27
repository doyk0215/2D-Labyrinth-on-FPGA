# Epic 3 Context: Roll the ball to the goal

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make the labyrinth playable: a ball falls under gravity that always points down on the screen, bounces slightly off maze walls without friction, and reaching the goal tile wins and starts a fresh maze. A reset always recovers a clean game, and the physics never makes the picture stutter. This turns the rotating maze from Epics 1–2 into the actual game.

## Stories

- Story 3.1: A ball that falls under screen-down gravity
- Story 3.2: Elastic wall collisions without friction
- Story 3.3: Reach the goal, win, and play again
- Story 3.4: Reset and frame-budget check

## Requirements & Constraints

- Gravity is constant and always points down on screen; in the maze frame it rotates opposite to the maze angle, including mid-rotation. Only rotating gravity is modelled (no centrifugal, Coriolis or moving-wall effects); the report must state this simplification.
- Ball position and velocity are fixed point and update exactly once per frame.
- On a wall collision the normal velocity component reverses and is scaled by a restitution below 1 (about 0.5–0.7). Tangential velocity is unchanged and no drag is applied anywhere.
- The ball must never pass through a wall or get stuck inside one. A speed cap is allowed and is part of the guarantee.
- The ball keeps its position relative to the maze when the maze rotates; collisions are computed in the maze frame.
- Reaching the goal cell enters WIN, then a new random maze. Reset returns to a clean state (with Epic 4 merged, reset returns to the menu).
- The physics step must finish inside vertical blanking so the game never stutters; the display stays at 60 fps without tearing.
- Timing must close at 100 MHz with no failing paths, within the resource budget (LUTs ≤ 50%, FFs ≤ 30%, BRAM ≤ 6, DSP48 ≤ 8).

## Technical Decisions

- **Physics frame:** the maze frame. Gravity in maze coordinates is `g·(sinθ, cosθ)`, from the same sin/cos the renderer uses.
- **Formats (single package file `labyrinth_pkg.vh`, no module hard-codes its own):** position signed Q9.8 maze pixels relative to the maze centre; velocity signed Q4.8 px/frame; tile 16 px; tile map 21×21 bits (1 = wall); ball radius 5 px; gravity 0.15 px/frame²; speed cap 5 px/frame per axis, so a 16 px wall can never be skipped.
- **Restitution:** shift-and-add only (e.g. 0.5 = `>>1`, 0.75 = `v − (v>>2)`). No runtime division; multipliers only in per-frame or per-scanline setup, within the DSP budget.
- **Collision method:** per-axis move and tile test — move along x, test the ball's bounding box against the tile map, and if blocked clamp to the tile edge and apply restitution to that axis's velocity; then the same for y. Goal detection is "ball centre inside the goal tile".
- **Start and goal placement (team decision 2026-10-28, implemented):** the ball spawns on the start tile, the bottom-right cell, drawn green; the goal is the top-left cell, drawn red. `maze_gen` sets both; `ball_physics` spawns on `start_*`.
- **Single writer:** `ball_physics` alone writes ball position and velocity. `maze_ram` is written only by `maze_gen` and read by physics (its own read port) and the renderer.
- **Timing of state changes:** all state changes happen on `frame_tick`, in vertical blanking; the renderer and ball overlay use a per-frame snapshot. Physics may take many clock cycles (vertical blanking is 45 lines, about 144,000 clocks at 100 MHz) but must finish before the first visible line.
- **Stage configuration:** `game_cfg` = `{rot_speed_sel[1:0], restitution_sel[1:0], n_cells[3:0]}`, written by `menu_ctrl` and latched by `game_ctrl` at game start (`active_game_cfg`).
- **Testbench rule:** every module has a self-checking bench printing PASS/FAIL, runnable in batch from Vivado; `ball_physics` must check no tunnelling and that the bounce ratio equals the restitution.

## Cross-Story Dependencies

- 3.2 builds on 3.1's `ball_physics` (gravity, cap, per-frame pipeline) and replaces its map-edge stop with tile collisions.
- 3.2 consumes the restitution selection that Story 4.2's stage menu already latches; exact restitution defaults per stage are tuned on hardware.
- 3.3 needs 3.2's collisions to reach the goal by play; it also drives `game_ctrl`'s WIN state (currently `in_goal` is tied low).
- 3.4 depends on all three and on Epic 4's MENU for reset behaviour.
