---
title: 'Story 3.2: Elastic wall collisions without friction'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_commit: '5bb45a97f51ce4ab727893213dfd92543252f252'
route: 'dispatch'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The ball falls straight through maze walls; `ball_physics` only stops it at the map edge, so the game cannot be played.

**Approach:** Replace the map-edge stop with AD-11's per-axis move and tile test: move x, test the ball's bounding box against `maze_ram` through the physics read port, clamp and bounce if blocked, then the same for y. The bounce scales the normal velocity by a shift-and-add restitution chosen by the stage's `restitution_sel`; tangential velocity is untouched.

## Boundaries & Constraints

**Always:** Ball box is the centre ±5 px (`BALL_RADIUS`). Restitution is shift-and-add on the magnitude, then the sign is reversed. Tiles outside 0..20 count as wall. The whole step runs in vertical blanking and ends with one `phys_done` pulse. `ball_physics` stays the only writer of ball state; it only reads `maze_ram`. The requested tuning is gravity 0.15 px/frame² with fractional carry, a 5 px/frame per-axis cap, and a spawn on the start tile, which is the bottom-right cell (green); the goal is the top-left cell (red) — see Spec Change Log.

**Decision — restitution per `restitution_sel`:** 0 → 0.5 (`v>>1`, EASY), 1 → 0.75 (`(v>>1) + (v>>2)`, HARD; changed by the human from `v − (v>>2)` in review pass 1 so bounces of 1–3 LSB round down and die out), 2 → 0.625 (`(v>>1) + (v>>3)`), 3 → 0.375 (`(v>>2) + (v>>3)`). HARD is bouncier; 2 and 3 are spares for the Story 4.3 settings screen.

**Never:** No multipliers or division in the collision path (the row × 21 address is shifts and adds). No drag or tangential change. No change to `maze_gen`, `render` or `ball_overlay` behaviour.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Free flight | no wall in the box's path | position += velocity, exactly as Story 3.1 | N/A |
| Hit a wall along x | leading edge would enter a wall column | x clamped so the box touches the tile edge; vx = −restitution(vx); vy unchanged | N/A |
| Hit a wall along y | same, along y, using the new x | y clamped; vy = −restitution(vy); vx unchanged | N/A |
| Diagonal corner tile | only the diagonal tile is wall | x moves freely, then y is blocked by it | N/A |
| Resting on a floor or in a corner | gravity into the wall every frame | position constant frame to frame; no jitter or creep into the wall | N/A |
| Small bounce | restitution(|v|) rounds to 0 | that axis stops (velocity 0) | N/A |

</frozen-after-approval>

## Code Map

- `rtl/ball_physics.v` -- Story 3.1 pipeline: gravity at `ft_d[1]`, velocity + cap at `go2`, position + map-edge stop + `phys_done` at `go3`. Keep the gravity, cap and `phys_init` logic; replace the `go3` stage with the collision step.
- `rtl/maze_ram.v` -- `raddr_p`/`rdata_p` is a synchronous read port (1-clock latency), currently unused. Address = row × 21 + col; bit 1 = wall. Do not change the module.
- `rtl/My_Top_Module.v:321` -- `assign maze_raddr_p = 9'd0;` to be driven by `ball_physics`; `ball_physics ball_i` instance at :345; `active_game_cfg[5:4]` is `restitution_sel` (`game_ctrl` output at :243).
- `rtl/labyrinth_pkg.vh` -- `POS_*`, `VEL_*`, `VEL_CAP`, `TILE_PX`, `MAP_DIM`, `MAP_ADDR_W`, `BALL_RADIUS`, `RESTIT_SEL_W`; add any new constants here (AD-4).
- `rtl/maze_gen.v` -- every tile outside the N-cell maze is written as wall, so the ball can never leave the maze.
- `tb/tb_ball_physics.v` -- Story 3.1 bench; assumes no walls (map-edge `LIMIT`, a start at row 0). Must gain a `maze_ram` instance and map loader.
- `tb/tb_top_ball.v` -- checks a long free fall from the spawn tile (bottom-right cell) with the 0.15 px/frame² model; walls now interrupt it.
- Geometry: maze pixel = Q9.8 position + 168 px; tile = maze pixel >> 4 (Q9.8: >> 12).

## Tasks & Acceptance

**Execution:**
- [x] `rtl/ball_physics.v` -- add `restitution_sel`, `maze_raddr`, `maze_rdata` ports; replace the position stage with a small FSM: x move, read the two tiles at the leading column, resolve (clamp + bounce or move), then y with the new x; drop `LIMIT`; `phys_done` after y -- AD-11.
- [x] `rtl/My_Top_Module.v` -- connect `ball_physics` to the physics read port and `active_game_cfg[5:4]`; update the comments.
- [x] `tb/tb_ball_physics.v` -- load maps into a real `maze_ram`; keep the 3.1 checks in an open room; add bounce-ratio (all four selections), tangential-unchanged, no-drag, corner-settle and a many-maps, many-angles no-tunnelling sweep that checks the box never overlaps a wall and no axis moves more than 5 px per frame.
- [x] `tb/tb_top_ball.v` -- replace the free-fall distance model with checks that hold with walls: the drawn ball matches the physics position, it moves down or rests at angle 0, and its box never overlaps a wall tile.

**Acceptance Criteria:**
- Given the full regression, when `tb/run_current_stories.tcl` runs, then every bench passes, including the extended `tb_ball_physics` and `tb_top_ball`.
- Given a routed build of `My_Top_Module`, when timing is reported, then there are no failing setup or hold paths at 100 MHz.
- Given the board in PLAY, when the maze is rotated, then the ball rolls along corridors, bounces off walls, and never passes through or sticks inside one.

## Design Notes

Box occupies `[c − R, c + R)` per axis (right/bottom edge exclusive), so the rows covered are `(y − R) >> 12` and `(y + R − 1) >> 12` in maze-pixel Q9.8 — at most two, because the box (10 px) is smaller than a tile. Moving +x into wall column `c`: clamp so that `x + R = 16c`; moving −x: `x − R = 16(c + 1)`. Because the box never overlaps a wall at the start of a frame and the cap (5 px) is less than a tile, only the leading column (or row) can be newly entered. The spawn tile is the green start tile in the bottom-right cell (`start_*`); `phys_init` zeros both velocity and the carried gravity fractions.

## Verification

**Commands:**
- `vivado -mode batch -source tb/run_current_stories.tcl` -- expected: `PASS regression ...` with no FAIL
- Routed non-project build of `My_Top_Module` -- expected: WNS ≥ 0, WHS ≥ 0, 0 failing endpoints

**Manual checks (if no CLI):**
- Board: ball rolls along corridors, bounces, settles in corners, never passes through walls.

## Implementation Notes

- Implemented directly (no subagent). Files: `rtl/ball_physics.v`, `rtl/My_Top_Module.v`, `rtl/labyrinth_pkg.vh` (`TILE_SHIFT`, restitution meaning on `RESTIT_SEL_W`), `tb/tb_ball_physics.v`, `tb/tb_top_ball.v`.
- Collision FSM: `S_IDLE → S_ADDR0 → S_ADDR1 → S_READ0 → S_RESOLVE` per axis (x then y); an axis with zero velocity skips its reads. `phys_done` now comes about 10 clocks after the velocity update instead of 1.
- `tb_top_ball`: also stopped holding BTNC as a reset (since Story 4.2 it is a debounced game-reset button; power-on reset starts the game).
- Verification: `tb/run_current_stories.tcl` passes (19 benches, both OLED modes). Sweep: 24 random maps, 5280 frames, 854 reversals, no overlap. Mutation check: dropping the second leading tile, a wrong 0.75 value, a bounce that zeroes the tangential velocity, a 1 px clamp error, and no x collision each make `tb_ball_physics` fail.
- Routed build: WNS +0.284 ns, WHS +0.049 ns, 0 failing endpoints; 2361 LUTs, 2072 FFs, 6 DSPs, 1.5 BRAM tiles. The new worst path starts at `ball_i/vel_y` (collision next-state logic) and ends in registers phys_opt moved out of the ball/overlay DSPs; margin is lower than before this story (+0.722).

- Review pass 1 fixes: HARD = `(v>>1)+(v>>2)` (human decision); −x/−y walls, odd speeds and the nominal ratio checked in `tb_ball_physics` (task `wall_hit`, all 4 walls × 4 restitutions × 4 speeds) plus a top-left corner settle; stage restitution checked at the top in `tb_top_story42_integration` (EASY → 0, HARD → 1); `tb_top_ball` asserts the ball dropped at least to its cell floor; epic context blanking figure corrected; `ball_physics` registers `p_clamp_r`/`p_free_r`/`v_bounce_r` in `S_READ0` for timing. Mutation check of the new tests: −x clamp off by 1 LSB, the old HARD formula, restitution wired to `[7:6]`, and `maze_rdata` stuck at 1 each fail.
- Final verification: `tb/run_current_stories.tcl` passes (19 benches, both OLED modes; sweep 861 reversals). Routed: WNS +0.469 ns, WHS +0.020 ns (OLED SPI register, untouched), 0 failing endpoints; 2333 LUTs, 2109 FFs, 6 DSPs (unchanged from before this story), 1.5 BRAM tiles. Board check not done yet.

## Spec Change Log

- **Review pass 1 (ECH1, intent gap):** HARD's `v − (v>>2)` keeps |v| = 1..3 LSB, against the matrix row "small bounce rounds to 0". The human chose `(v>>1) + (v>>2)` and asked to keep the existing code rather than revert. Amended: the frozen restitution decision (by the human). Avoids: tiny bounces that never decay at HARD. KEEP: the per-axis FSM, the two-read leading-edge test, the restitution on the magnitude, and every existing bench check.
- **Tuning commit 4b1fb42 (eziqnah):** gravity 0.15 px/frame² (constant multiply by 2458 = 0.15 in Q14, 20-bit fraction carried), cap 5 px/frame, ball spawned on `goal_*` (the bottom-right cell). Verified 2026-10-28: regression passes (19 benches, both OLED modes); routed WNS +0.747 ns, WHS +0.094 ns; 2305 LUTs, 2044 FFs, 1.5 BRAM, **8 DSPs** (the AD-8 cap; the gravity multiply adds 2). Board check not done.
- **Start/goal swap (team decision 2026-10-28, implemented):** the spawn stays in the bottom-right cell, but that cell is now the **start** tile drawn **green**, and the top-left cell is the **goal** drawn **red**. `maze_gen` swaps its start/goal assignments; `My_Top_Module` wires `ball_physics` `spawn_*` to `start_*`; `tb_maze_gen`, `tb_render`, `tb_top_story14_integration`, `tb_top_story42_integration` and `tb_top_ball` expect the new tiles. Avoids: spawning on the goal tile, which wins at once under the AD-11 goal test (Story 3.3). Verified: regression passes (19 benches, both OLED modes); routed WNS +0.729 ns, WHS +0.070 ns; 2312 LUTs, 2044 FFs, 8 DSPs, 1.5 BRAM. Board check passed 2026-10-28 (f00f99c): green start bottom-right with the ball spawning there, red goal top-left, physics as before with the 0.15 gravity and 5 px/frame cap.
- **Gravity multiply out of DSPs (2026-10-28):** the constant multiply by `GRAVITY_Q14` is marked `use_dsp = "no"`, so Vivado builds it from shifted adds in LUTs; behaviour is bit-identical. Returns DSP use to 6 of the AD-8 cap of 8. Verified: regression passes; routed WNS +0.365 ns (worst path the existing `vel_y` collision logic), WHS +0.075 ns; 2512 LUTs, 2242 FFs, 6 DSPs, 1.5 BRAM.

## Review Triage Log

Review pass 1 (blind-hunter BH, edge-case-hunter ECH, verification-gap VG):

| # | Finding | Verdict | Evidence | Route |
|---|---------|---------|----------|-------|
| ECH1 | HARD (`m - (m>>2)`) keeps \|v\| = 1..3 LSB, so tiny bounces never decay | medium | `mag - (mag>>2)` = `mag` for mag 1..3; contradicts the matrix row "small bounce rounds to 0 → axis stops". The formula is written in the frozen decision | intent_gap |
| VG1 / BH3 | −x / −y clamp and bounce never checked exactly | medium | Tests 6, 10–14 all hit +x or +y; the sweep only checks overlap and a reversal count, so a −side clamp 1 LSB short or a wrong −side bounce passes | patch |
| VG2 / BH6 | Stage restitution reaching `ball_physics` untested at top | medium | `tb_top_ball` uses `START_IN_MENU=0` (sel always 0); `tb_top_story42` never reads `ball_i`; wiring `[7:6]` or `2'd0` would pass | patch |
| BH2 | Bounce check mirrors the RTL formula; hit speeds are multiples of 64, so truncation is never exercised | low | `bounce()` copies the RTL; k·64 speeds make every shift exact | patch |
| BH5 | `tb_top_ball` accepts a frozen ball (y1 == y0 == tile centre) | medium | A top-level wiring fault (e.g. `maze_rdata` stuck at 1) keeps the ball still; `tb_ball_physics` drives its own RAM so would not see it | patch |
| BH9 | Epic context says "a few hundred cycles" of blanking | low | Vertical blanking is 45 lines × 3200 clocks ≈ 144k clocks (`vga_timing`); direct wording fix | patch |
| BH9b | WNS fell to +0.284 ns | medium | Re-graded after the patch build: routed WNS fell to +0.012 ns on `axis` → clamp/next-position adders → `ball_x/y` (run-to-run placement variation). Fixed by registering the clamp, free position and bounce in `S_READ0` (no extra cycles); WNS back to +0.469 ns | patch |
| BH1 | 0.75 / 0.375 outside "about 0.5–0.7" | false | Human chose option A explicitly at planning; recorded in the frozen decision | reject |
| BH4 | Out-of-map path untested; address can exceed 440 when out of map | low | Unreachable: every map border is wall (`maze_gen` writes all non-maze tiles as wall); when out of map `blocked` is forced to 1 (`1 | X = 1`) | reject |
| BH7 | Resting ball keeps a non-zero stored velocity | false | Matrix row covers only bounces that round to 0; settling at about −21 is documented in Design Notes and the position never changes (test 6) | reject |
| BH8 | `phys_init` or a new `go3` while the FSM is busy | false | `go3` comes once per frame (≈1.67 M clocks apart, FSM ≈ 12 clocks); `phys_init` fires on the GENERATE→PLAY edge while `phys_en` was 0, so the FSM is idle | reject |
| BH10 | Constants literal or repeated (`TILE_SHIFT`, restitution table, tb constants) | low | Cosmetic; `TILE_SHIFT` is in the package as AD-4 requires | reject |
| BH11 | Diagonal test does not assert the clamped y | low | Same +y clamp path is checked exactly by tests 6 and 14; the overlap check covers the diagonal | reject |
| BH12 | Spec completion record lacks board result, tuning, DSP baseline | false | Board check is pending by design; fix would edit this spec; DSPs were 6 before this story too (PR #40 build) | reject |
| ECH2 | Ball already inside a wall at frame start | false | Unreachable: the start tile is always floor and the map only changes in GENERATE, after which `phys_init` re-places the ball | reject |
| ECH3 | `tb_top_ball.box_in_wall` has no bounds check | low | Escape is unreachable (border walls); adding the guard is new logic | reject |
| ECH4 | `tb_top_ball` y1 < y0 − 1 may false-FAIL on a rebound | false | Bench runs restitution 0 only; rebound peak ≤ 0.25 × 3 px = 0.75 px with a wall below, and any deeper floor rebounds far below y0 | reject |
