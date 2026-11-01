# Epic 7 Context: Bigger and harder mazes

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Add a third stage, N = 15 (a 31 x 31 tile map), and mazes with more than one route on HARD and larger. v1 has two stages (N = 5 and N = 10) whose whole map fits on the 640 x 480 screen at any angle; the N = 15 map does not (31 tiles x 16 px = 496 px, about 700 px across the diagonal), so it is viewed through a camera that follows the ball. N = 5 and N = 10 must look and play as they do today.

## Stories

- Story 7.1: Map size follows the stage
- Story 7.2: Camera that follows the ball
- Story 7.3: Draw the N = 15 map
- Story 7.4: Add the N = 15 stage
- Story 7.5: Loops on HARD and larger

## Requirements & Constraints

- The maze stays playable at every rotation angle; the ball must stay on screen.
- The view must not shake when the ball bounces (bounces are about 21 px high at EASY restitution and 47 px at HARD).
- The existing N = 5 and N = 10 regression passes unchanged.
- Routed timing at 100 MHz stays met, and DSPs stay within the 8-DSP budget; the physics step still finishes in vertical blanking.
- Everything drawn changes only in vertical blanking, so a frame never mixes two camera positions or states.

## Technical Decisions

- Positions are signed Q9.8 maze pixels relative to the active map's centre; velocities are signed Q4.8 px/frame with a 5 px/frame cap per axis. Tile 16 px, ball radius 5 px.
- All widths and scales live in `labyrinth_pkg.vh` (shared, owner DY; changes need all three owners). No module hard-codes its own.
- The maze is stored at a fixed 32-tile row (`addr = {row, col}`, 1,024 tiles); the active (2N+1) x (2N+1) map sits from the top-left with centre tile N.
- The camera keeps the 16 px tile, so physics, the ball and the goal test do not change. A new `camera` module is the single writer of `cam_x`, `cam_y` (Q9.8, the ball's format). It updates once per frame on `phys_done`, uses a dead zone (about +/-48 px), smooths with `cam += (target - cam) >>> CAM_SHIFT` (shift and add only), snaps to the ball on `phys_init`, and outputs the map centre for N = 5 and N = 10.
- `render` will take the camera position in place of its fixed map centre, registering the per-frame part of the scanline start in vertical blanking; `ball_overlay` will take `ball - cam`. Render's sin/cos snapshot is taken before physics runs, so the camera must not be captured with it.
- Multipliers are limited to the per-frame and per-scanline setup; no runtime division.
- One owner per file: DY owns `render`, `maze_ram`, `ball_overlay`, `vga_timing`, `My_Top_Module.v`, the XDC and the new `camera`; QZ owns `ball_physics` and `maze_gen`; CJX owns `game_ctrl`, `menu_ctrl` and `oled_status_text`. A story touching another person's file is paired.
- Board checks are done by someone other than the story's author.

## UX & Interaction Patterns

- N = 15 appears as a third menu entry (for example STAGE 3 HUGE) selected with btnU and btnD; the OLED shows its name and timer like the other stages.
- On N = 15 the ball starts at the bottom-right start tile and the goal is at the top-left.

## Cross-Story Dependencies

- 7.1 (merged) is the base for all others. 7.2 needs 7.1; 7.3 needs 7.1 and 7.2; 7.4 needs 7.1 and 7.3; 7.5 needs 7.1.
- 9.1 (item boxes) needs 7.5.
- 8.2's time limit for N = 15 is 180 s.
