---
title: 'Story 9.1: Place and draw item boxes'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_commit: '978d16d90963d67635bc26caa93babe6f77f26f3'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 9 needs item boxes in the maze, but nothing places or draws them yet, so Story 9.2 (pickup and effects) has nothing to pick up.

**Approach:** At the end of each generation, `maze_gen` places one box in each quadrant of the cell grid (boxes 0 and 1 buff, 2 and 3 debuff; a seeded shuffle picks which quadrants get the buffs) and outputs their tile coordinates like `start_*`/`goal_*`.

**Decisions (DY, 2026-11-02):** DY writes all of 9.1, including the `maze_gen` placement first assigned to QZ; QZ reviews. Boxes are spread one per quadrant rather than at uniformly random cells, so they cannot cluster. `render` draws a box on those tiles: a buff box (blue fill, green outline) and a debuff box (red), each with a white "?" glyph, turning with the maze.

## Boundaries & Constraints

**Always:**
- Boxes sit on cell tiles (odd column and row) inside the active map, never on the start or goal cell, and no two share a cell. Quadrants split the cells at h = N/2 (rounded down): 0 top-left (columns and rows < h), 1 top-right, 2 bottom-right, 3 bottom-left; the goal is in quadrant 0 and the start in quadrant 2. A box is drawn on floor; it never changes `maze_ram` or blocks the ball.
- Positions come only from the seeded `rng` after the maze and its loops are built, so the maze itself (and EASY's map) is unchanged and the boxes are the same for the same seed.
- `maze_gen` stays the only writer of `maze_ram` (AD-5). Box storage is registers in `maze_gen` (4 x {row, col}, 40 bits) plus a `box_valid` bit per box, cleared when a generation starts.
- `render` draw order: WIN panel, ball, start, goal, box, wall, floor. The glyph is drawn in maze space (it rotates with the map), from the tile-local pixel bits `walk_*_q[17:14]`.
- `render` takes a `box_visible[3:0]` input, ANDed with `box_valid`; the top ties it high (Story 9.2 will drive it from `item_ctrl`).

**Never:**
- No pickup, effect, respawn or OLED change (Stories 9.2 and 9.7). No change to `ball_physics`, `maze_ram` width or the loop pass.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Any stage, N >= 4 (menu: 5, 10, 15) | gen_done | 4 valid boxes, one per quadrant, not start/goal | N/A |
| N = 2 or 3 (legacy switches only) | a quadrant holds only the start or goal | no boxes (`box_valid = 0`) | N/A |
| Buff placement | seed | buffs in two quadrants chosen by the seed, any of the 6 pairs possible | N/A |
| New generation starts | gen_start | `box_valid` clears until the new boxes are placed | N/A |
| Same seed twice | same N, seed | same maze and same box positions | N/A |
| Box pixel | box tile, tile-local (x, y) | outline, fill or white "?" per the 16 x 16 mask | N/A |

</frozen-after-approval>

## Code Map

- `rtl/maze_gen.v` -- add box states after the loop pass (and after the DFS when K = 0); box k goes in quadrant (r + p_k) mod 4, with r = 2 seeded bits and p = (0, 1, 2, 3), or (0, 2, 1, 3) when a seeded swap bit is set; inside its quadrant, rejection-sample column and row offsets from `rng` (each < quadrant size), rejecting the start or goal cell; outputs `box_cols[19:0]`, `box_rows[19:0]` (tile coords, box k at bits 5k+4:5k) and `box_valid[3:0]`. Reuse `xorshift` and the `S_PICK` rejection pattern.
- `rtl/render.v:170-221` -- add `is_box_d[3:0]` beside `is_start_d`/`is_goal_d` (same pipeline edge), register the tile-local pixel bits, and a box branch in the colour mux after goal. Colours as localparams next to `START_*`.
- `rtl/My_Top_Module.v:375-389, 483-507` -- wire `maze_gen` box outputs to `render`; `box_visible` = 4'b1111.
- `tb/tb_maze_gen.v` -- per run: valid boxes for N >= 4 (none for N = 2, 3), one in each quadrant, cell tiles inside the map, floor in `mem`, not start/goal, distinct; include box coordinates in `mem_hash` so determinism covers them.
- `tb/tb_render.v:105-123` -- expected colour at each box tile's sampled pixel (8, 8); plus a box check of outline, fill and glyph pixels on one buff and one debuff box.
- `tb/tb_rotated_render.v`, `tb/tb_story71_map.v`, `tb/tb_story73_render.v`, `tb/tb_win_render.v`, `tb/tb_game_state_encoding.v` -- instantiate `render` directly; tie the new inputs off (`box_valid` 0).
- Do not touch `ball_physics.v`, `maze_ram.v`, `camera.v`, `oled_*`.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/maze_gen.v` -- box placement and outputs -- positions for 9.1 and 9.2
- [x] `rtl/render.v` -- box drawing -- the player sees the boxes
- [x] `rtl/My_Top_Module.v` -- wiring -- connect generator to renderer
- [x] `tb/tb_maze_gen.v`, `tb/tb_render.v` and the direct `render` benches -- checks and tie-offs -- the I/O matrix
- [x] Story file `_bmad-output/implementation-artifacts/9-1-place-and-draw-item-boxes.md` -- record results -- issue workflow

**Acceptance Criteria:**
- Given a buff, a debuff, the start and the goal tile on screen, when compared, then each has a different colour away from the glyph (box fill 0x04F and 0xC00, start 0xF00, goal 0x0F0) and the boxes show white "?" pixels inside a coloured box with a floor margin.
- Given the full regression and routed build, when run, then everything passes and LUT, FF and timing caps (AD-8) are met.

## Design Notes

Box mask on the 16 x 16 tile: floor margin at x or y = 0 or 15; outline at x or y = 1 or 14; fill inside; glyph (6 x 9, columns 5-10, rows 3-11) white:

```
.####.   ##..##   ....##   ...##.   ..##..   ..##..   ......   ..##..   ..##..
```

Buff: fill 0x04F (blue), outline 0x0F0 (green). Debuff: fill 0xC00, outline 0xF88. Start stays solid 0xF00 and goal solid 0x0F0, with no glyph or margin.

## Verification

**Commands:**
- `vivado -mode batch -source tb/run_current_stories.tcl` (from a short C:\ folder) -- expected: all PASS
- `vivado -mode batch -source scripts/check_timing.tcl` (TEMP set short) -- expected: timing met, AD-8 caps met

## Implementation Notes

- Implemented directly (DY asked for no implementation subagent); three review subagents ran on the diff.
- `tb_render` checks all four boxes, not one buff and one debuff as the Code Map said. Each box is sampled on its centre scanline only (margin, outline, fill, glyph); the full mask, rotation and the `box_visible`/`box_valid` gate are checked in `tb_rotated_render`, added after review.
- The colour AC was reworded from "at the tile centre" to "away from the glyph": the centre of a box is the white "?", like a wall's centre.
- After review, `box_cols`/`box_rows` clear on reset and on `gen_start`, so an N < 4 maze leaves them zero.

## Spec Change Log

## Review Triage Log

| Finding | Verdict | Evidence | Route |
|---|---|---|---|
| Box mask only checked on one scanline, at 0 degrees; rotation and the "?" shape untested (blind, edge-case, verification-gap) | medium | `tb_render` samples local row 8 only; the rotation bench tied `box_valid` to 0 | patch: boxes added to `tb_rotated_render` with an independent mask model at 0/45/90/135 degrees |
| `box_visible` gate untested | low | every bench tied it to 1111 | patch: `tb_rotated_render` hides box 1 with `box_visible` and leaves box 3 invalid |
| Story says `tb_render` checks "each box's ... pixels" and "exactly four boxes are drawn" | low | it counts box coordinates in the map and samples one row | patch: story wording |
| Buff outline 0x0F0 equals the goal green; buff and debuff differ by colour only | low | real, but blue fill with green outline is the frozen intent, and the box has a margin and a "?" the goal lacks | reject |
| Quadrant pairs not uniform; docs say only "any pair" | low | adjacent pairs 1/8 each, diagonal pairs 1/4 each | patch: comment and story state the odds |
| Stale `box_cols`/`box_rows` when N < 4, and the determinism hash includes them | low | nothing cleared them; no current same-seed test runs at N < 4 | patch: clear on reset and `gen_start` |
| `box_valid` bits rise one at a time while `gen_busy` | low | consumers read after `gen_done`; the map is still being written then | reject |
| Header still says "contract v1.0"; workstreams doc not updated for the owner change | low | no consumer breaks; the decision is in the story and spec | reject |
| Widths hard-coded `[19:0]` and `5*bi` instead of `COORD_W` | low | matches the existing hard-coded `[4:0]` start/goal ports | reject |
| Rejection loop in `S_BOX` has no retry cap | low | same pattern as `S_PICK`; full-period xorshift; longest of 563 runs 2,559 cycles | reject |
| A box can sit next to the start or goal | maybe-false | matters only once 9.2 adds pickup | defer (deferred-work.md) |
| Story lacks an AD-8 cap statement | low | it lists counts only | patch: story states the caps |
