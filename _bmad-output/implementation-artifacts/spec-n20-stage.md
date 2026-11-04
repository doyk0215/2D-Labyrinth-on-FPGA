---
title: 'N = 20 maze support (41 x 41 tiles), tested on its own'
type: 'feature'
created: '2026-11-03'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '3fdc74d22c515201622d1e31c62514abf5cd0967'
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-2D-Labyrinth-on-FPGA-2026-10-23/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The largest maze is N = 15 (31 x 31 tiles). Tile coordinates are 5 bits, the map store is 32 x 32 and N is 4 bits, so a bigger maze cannot be represented.

**Approach:** Widen the shared map format to 6-bit tile coordinates, a 64-tile stored row and a 5-bit N, so the generator, physics, renderer and items work on N = 20. A top-level parameter `TEST_N_CELLS` (default 0 = off) forces every game to that N, for a separate test build. DY implements all of it; the `labyrinth_pkg.vh` change counts as approved by DY, QZ and CJX (DY, 2026-11-03). DY, 2026-11-03: "do not touch on the oleds yet. we will test on n=20 separately then take integration step later" — the menu stage, OLED text, stage name and HIGH score for N = 20 are a later integration step. N = 20 values: time limit 240 s, loops K = 6, boxes 3 buff + 3 debuff.

## Boundaries & Constraints

**Always:** N = 5, 10 and 15 keep identical mazes, loops, box positions, timing values and pictures for every seed. With `TEST_N_CELLS = 0` the design behaves exactly as main 3fdc74d. Timing met at 100 MHz and the AD-8 caps hold (LUT <= 10,400, FF <= 30%, BRAM <= 6, DSP <= 8). No runtime multiply or divide in new logic.

**Never:** No change to `menu_ctrl`, `game_ctrl`, `oled_status_text`, the OLED path or `game_cfg` (stays 8 bits). No change to physics constants, speed cap, fog radius, item durations or the menu background (stays N = 15). The legacy `START_IN_MENU = 0` switch path stays 4-bit. No Vivado IP.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Test build | `TEST_N_CELLS = 20`, any menu stage, C | N = 20 maze: start tile (39,39), goal (1,1), countdown 4:00 | N/A |
| Far tiles | Ball, box or render pixel at column or row 32..40 | Reads, draws and picks up that tile, not tile (c-32) | N/A |
| Out-of-range N | `n_cells` 21..31 or 0..1 into `maze_gen` | Clamped to 20 or 2 | Clamp |
| Normal build | `TEST_N_CELLS = 0` | Same stages, mazes and pictures as main | N/A |

</frozen-after-approval>

## Code Map

- `rtl/labyrinth_pkg.vh` -- `MAX_N_CELLS` 20, `N_CELLS_W` 5, `COORD_W` 6, `MAP_DIM` 41, `MAP_STRIDE` 64, `MAP_TILES` 4096, `MAP_ADDR_W` 12, `MAP_MID` 20.
- `rtl/maze_ram.v` -- sized by the macros; init loop hard-codes 32 (keep the 21 x 21 fixed map at rows/cols 0..20).
- `rtl/maze_gen.v` -- ports already use the macros. Internal: `n`, `cx`, `cy`, `nx`, `ny`, `nm1`, `scx`, `scy`, `band_*`, `half`, `rand_*`, `box_cx/cy` 4-bit; tile wires 5-bit; `clr_addr` 10-bit; `visited` a 256-bit register cleared in S_INIT; `open_e/open_s` 256 entries; `stack` 225 x 8, `sp` 8-bit; `loop_cap`/`box_target` test `n == 10/15`; S_IDLE clamps only the low end; loop column `rng[3:0]`, box cell `rng[2:0]`/`rng[6:4]`.
- `rtl/ball_physics.v` -- only `active_dim` (5-bit) and `in_map`'s `{3'b0, active_dim}`.
- `rtl/render.v` -- `n_cells [3:0]`, `active_dim`, `n_ext {23'd0,n}`, `tile_*_now = walk_*_q[22:18]`, `maze_raddr [9:0]`, start/goal `[4:0]`, box buses `[29:0]` with `5*bi +: 5`, buff/debuff split `n_cells == 4'd15`.
- `rtl/item_ctrl.v` -- `n_cells [3:0]`, box buses `[29:0]`, `centre {15'd0,n}`, `map_limit {14'd0,n,1'b0}`, `ball_col/row = absolute_*[16:12]`, `k*5+:5`, `buff_count` tests `== 15`.
- `rtl/game_timer.v` -- `n_cells [3:0]`, limit case 5/15/default; add `XL_SECONDS` for N = 20.
- `rtl/game_status_hud.v` -- `n_cells [3:0]` (only `!= 5`).
- `rtl/camera.v`, `rtl/ball_overlay.v` -- width-generic; no change (camera follows for N >= 11).
- `rtl/My_Top_Module.v` -- coords/boxes 262-269, `gen_n_cells` 288, `n_cells` 419-420, menu background `4'd15` 444/762, high-score case 511-517 (skip when `TEST_N_CELLS != 0`), timer params 523-525.
- `scripts/build_bitstream.tcl` -- optional `TEST_N_CELLS` from the environment as a top generic.
- Benches to check (stride-32 addresses, 5-bit box packing, truncating output wires): `tb_ball_physics`, `tb_fog_render`, `tb_item_gravity`, `tb_maze_gen`, `tb_render`, `tb_rotated_render`, `tb_story71_map`, `tb_story71_physics`, `tb_story73_render`, `tb_top_ball`, `tb_top_story14_integration`, `tb_top_story33_control`, `tb_top_story44_integration`, `tb_top_story74_stage`, `tb_top_story83_time_up`, `tb_top_story92_items`, `tb_top_story97_roulette`, `tb_item_ctrl`, `tb_item_roulette`, `tb_story95_items`, `tb_top_story95_buffs`. Some matches are false positives.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/labyrinth_pkg.vh`, `rtl/maze_ram.v` -- widths above; init loop over `MAP_STRIDE`.
- [x] `rtl/maze_gen.v` -- widen internals; `visited` becomes LUT RAM cleared during S_CLEAR and set in S_INIT/S_WCELL; 1024-entry passage records; 400 x 10 stack, 9-bit `sp`; clamp N to 2..20; `loop_cap` 6 and `box_target` 6 for N = 20, box split `n >= 15`; for N > 15 only, loop column from `rng[4:0]`, box cells from `rng[3:0]`/`rng[7:4]` with rejection.
- [x] `rtl/ball_physics.v`, `rtl/render.v`, `rtl/item_ctrl.v`, `rtl/game_status_hud.v`, `rtl/game_timer.v` -- macro widths, `[23:18]`/`[17:12]` tile slices, `COORD_W` box packing, `n >= 15` splits, `XL_SECONDS`.
- [x] `rtl/My_Top_Module.v`, `scripts/build_bitstream.tcl` -- widths, `TEST_N_CELLS`, `XL_TIME_SECONDS = 240`.
- [x] Benches in the Code Map -- addresses via `MAP_STRIDE`, box packing via `COORD_W`, output widths.
- [x] `tb/tb_maze_gen_golden.v` (new) -- N = 5/10/15 maze and box checksums for 16 seeds equal values captured on main 3fdc74d.
- [x] `tb/tb_n20_maze.v`, `tb/tb_n20_play.v` (new) -- N = 20 maze connected and solvable for many seeds, stack <= 400, loops <= 6, boxes valid and distinct with some at quadrant offset >= 8, tiles outside 41 x 41 are wall; physics no tunnelling and goal bounds; render matches RAM at columns/rows 32..40 at 0 and 45 degrees; item pickup at column >= 32.
- [x] `tb/tb_top_n20.v` (new) -- `TEST_N_CELLS = 20`: GENERATE, start/goal tiles, 4:00 countdown.
- [x] `tb/run_n20.tcl` (new) -- runs the new benches.

**Acceptance Criteria:**
- Given main's benches, when run after the change, then every bench that passed on main 3fdc74d still passes.
- Given a normal and a `TEST_N_CELLS = 20` routed build, when reported, then WNS >= 0, WHS >= 0 and every AD-8 cap holds.

## Implementation Notes

- **Matrix audit.** Test build: `tb_top_n20` (N = 15 backdrop, N = 20 game, start (39,39), goal (1,1), 4:00, follow camera, BFS-reachable goal, WIN, HIGH scores untouched). Far tiles: `tb_n20_play` (wall clamps at tiles 36 and 40, goal (39,39), pickup at (35,37) but not its alias (3,5), debuff at (33,39)) and `tb_n20_render` (6,660 checked pixels at tiles 32..40, box at (35,37) drawn). Out-of-range N: `tb_n20_maze` clamp 0/1/21/31. Normal build: `tb_maze_gen_golden` (224 checksums, N = 2..15 x 16 seeds, captured on main) plus the full regression below.
- **Mutation checks.** The old `[16:12]` slice in `item_ctrl` fails `tb_n20_play`; the old `[22:18]` slice in `render` fails `tb_n20_render`; forcing `wide = 1` in `maze_gen` fails `tb_maze_gen_golden`; the old `n_cells == 15` buff/debuff split in `render` fails `tb_n20_render` (after the review patch below).
- **Routed builds** (Vivado 2025.2, `scripts/build_bitstream.tcl`). Normal: WNS +0.070 ns, WHS +0.075 ns, 6,165 LUT, 6,882 FF (16.5%), 3.5 BRAM, 6 DSP. `TEST_N_CELLS=20`: WNS +0.224 ns, WHS +0.060 ns, 6,098 LUT, 6,773 FF (16.3%), 3.5 BRAM, 6 DSP. Every AD-8 cap holds. Against main 3fdc74d (5,669 LUT, 4,925 FF) the growth is all in `maze_gen` (FF 2,225 -> 4,180, LUT 1,798 -> 2,243): its DFS stack is flip-flops, as on main, now 400 x 10 bits; `visited` moved to 192 LUTRAM as planned.
- **Review.** Subagents are used only when DY asks, and none were asked for here, so the three review layers (blind, edge case, verification gap) were run in this session over the staged diff, not by separate reviewers.
- **Regression.** Every bench in `run_current_stories.tcl` was run on main 3fdc74d and on this branch, without stopping at the first failure: the same 33 pass (`tb_top_story73_camera` and `tb_top_ball` run alone, without the 10-minute hang watchdog), and the same 17 fail on both with identical messages (menu-era top benches, `tb_maze_gen` N = 5 boxes, OLED/menu/switch unit benches; all stale on main, not caused by this work). `tb_top_win_indication` hangs after its timeout on main too (`$fatal` in a task does not stop xsim).
- **Bench edits.** Legacy benches moved to `MAP_STRIDE` addressing, `COORD_W` box packing and `N_CELLS_W`/`COORD_W`/`MAP_ADDR_W` signal widths. xsim leaves the upper bit of a wider input port undriven (X) when a narrower reg is connected, so 4-bit `n_cells` regs were widened, not just left to zero-extend.

## Spec Change Log

## Review Triage Log

| # | Layer | Finding | Verdict | Evidence | Route |
|---|-------|---------|---------|----------|-------|
| 1 | verification-gap | `render`'s buff/debuff split `n_cells >= 15` is not exercised at N = 20: the box sat in slot 0, a buff under either split, and any non-floor colour passed | low | Mutant `n_cells == 15` passed the old bench; box moved to slot 2 and debuff colours `f88`/`c00` rejected, and the mutant now fails | patch (`tb/tb_n20_render.v`) |
| 2 | blind | `maze_gen` comment on `box_target` still says "6 HUGE" | low | Six boxes now apply from N = 15 up | patch (`rtl/maze_gen.v`) |
| 3 | edge-case | `TEST_N_CELLS` is not range-checked: 16..19 gives no loops and the 120 s default timer, above 31 truncates | low | True, but only a hand-set test generic; a guard adds logic for a value nobody builds | reject |
| 4 | edge-case | Every generation now clears 4096 tiles, 3072 more cycles (about 31 us) for N <= 15 too | false | Generation is not on any timed path; the full regression and golden checksums match main | reject |
| 5 | blind | For N = 20 the loop scan's start column is biased (columns 0..11 twice as likely) | low | Only the scan start moves; the opened wall is still the first closed one in the band. Cosmetic | reject |
| 6 | edge-case | `item_ctrl` 19-bit `centre`/`absolute_*` and `ball_physics` `AW = 19` overflow at N = 20 | false | Largest value is 20*4096 + 2048 + 20.5*4096, about 167,936 < 2^18; `in_map`'s 7-bit tile index covers -64..63 against tiles 0..41 | reject |
| 7 | edge-case | Modules still taking a 4-bit `n_cells` would truncate 20 to 4 | false | Every `.n_cells(...)` in `My_Top_Module` goes to a module whose port is `N_CELLS_W` (`camera` already was) | reject |
| 8 | verification-gap | `run_current_stories.tcl` stops at the first failure and 17 benches already fail on main | high | Pre-existing on main 3fdc74d, identical messages | defer |
| 9 | verification-gap | `$fatal` in bench `fail` tasks does not stop xsim, so failing benches hang | medium | Pre-existing: `tb_top_win_indication` ran over 2 h on main after its timeout | defer |
| 10 | verification-gap | The N = 20 suite, including the N <= 15 golden check, is outside `run_current_stories.tcl` | medium | Needs `-i tb` and an explicit list entry; worth folding in with the stale-bench repair | defer |

## Design Notes

`visited` as a 1024-bit register would add about 770 flip-flops and four 1024:1 multiplexers; LUT RAM with four read ports costs about 100 LUTs. New random picks only when `n > 15` keep the N <= 15 streams bit-exact, which the golden-checksum bench proves. `TEST_N_CELLS` keeps the N = 20 test out of `game_cfg` and the menu, so the later integration step owns those changes.

## Verification

**Commands:**
- `vivado -mode batch -source tb/run_n20.tcl` (TEMP set to a short folder) -- expected: all PASS.
- `vivado -mode batch -source tb/run_current_stories.tcl` -- expected: same PASS set as on main 3fdc74d (`tb_top_story97_roulette` already fails there).
- `scripts/build_bitstream.tcl`, normal and with `TEST_N_CELLS=20` -- expected: timing met, AD-8 caps hold.
