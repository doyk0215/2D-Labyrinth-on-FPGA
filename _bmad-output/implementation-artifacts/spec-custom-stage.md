---
title: 'Menu stages EASY / MEDIUM / HARD / CUSTOM with a switch-set maze size'
type: 'feature'
created: '2026-11-04'
status: 'done'
baseline_commit: '0972013fe93ac7f6be1feb5ef36956a752c654e7'
route: 'dispatch'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** N = 20 mazes can only be played through the `TEST_N_CELLS` test build, and the menu offers three fixed sizes. DY wants players to pick any size up to 20, with the size set on the switches.

**Approach:** SW4..SW0 give a custom maze size. The OLED menu shows four entries: EASY (N = 5), MEDIUM (N = 10), HARD (N = 15) and CUSTOM (the switch size). Snap rotation moves to SW15 and the fixed seed to SW14. Every stage parameter becomes a function of N that is valid for N = 2..20. The `TEST_N_CELLS` path is removed.

DY's decisions (2026-11-04):
- EASY 5, MEDIUM 10 (was HARD), HARD 15 (was HUGE). N = 20 is reachable only through CUSTOM.
- CUSTOM accepts 2..20. It rejects 0, 1 and 21..31.
- The menu has no "L=SET C=GO" line. EASY, MEDIUM and HARD keep `HIGH=n`. The CUSTOM line shows the live switch value, e.g. `CUSTOM N=17`. Custom games never update a HIGH score.
- BTNC on CUSTOM with an invalid size shows an error for about 2 s (`CUSTOM SIZE` / `INVALID: N=25` / `USE 2-20 ON` / `SW4-SW0`), then the menu returns with the selection unchanged. Nothing else changes.
- Per-size values are placeholders. DY will confirm them in a playtest.

## Boundaries & Constraints

**Always:**
- EASY, MEDIUM and HARD keep today's values for their N: time limit, boxes, loops, bounce, and the maze for a given seed (the golden mazes stay bit-exact).
- BTNL still opens settings and BTNR still opens instructions. U/D wrap through four entries.
- Switch inputs are synchronised (two flip-flops) like SW0 today.
- Benches keep their meaning. Only switch values, text and widths change.

**Never:**
- Change the OLED driver, mailbox or font.
- Change the VGA menu overlay, LEDs or item effect timing.
- Change the menu backdrop, which stays N = 15.
- Add runtime division to game_timer.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Preset start | EASY/MEDIUM/HARD + BTNC | N = 5/10/15 game exactly as today. HIGH updates on a win. | N/A |
| Custom start | CUSTOM, SW4..0 = 20 + BTNC | N = 20 game, 4:00, 6 boxes, 6 loops. No HIGH update. | N/A |
| Custom small | SW = 2 | 2 x 2 maze, 0:24, no boxes, no loops. Win works. | N/A |
| Invalid size | SW = 0, 1 or 21..31 + BTNC | Error text for about 2 s, then the menu. No game starts. | Buttons are ignored during the error. |
| Switch moves mid-game | Change SW4..0 in PLAY | Size unchanged, including on BTND regenerate and next level | N/A |
| Snap / seed | SW15, SW14 | Snap rotation / fixed seed. SW0 and SW5 no longer do this. | N/A |

</frozen-after-approval>

## Code Map

- `rtl/menu_ctrl.v`: stage table, OLED menu text, U/D/C handling.
  - Add input `custom_n[4:0]` and parameter `ERROR_HOLD_CYCLES`.
  - Selection becomes 0..3.
  - `game_cfg` becomes 10 bits: `{custom, rot[1:0], rest[1:0], n[4:0]}`.
  - Add the error page.
- `rtl/game_ctrl.v`: latches `game_cfg` into `active_game_cfg` (lines 18, 31, 67, 87, 98). Widen both to 10 bits, with reset `{1'b0,2'b00,2'b00,5'd5}`.
- `rtl/My_Top_Module.v`:
  - Switch sync: `snap_sw_sync` uses `sw[15]`; `debug_fixed` uses `sw[14]`.
  - Add a synchronised `sw[4:0]` that feeds menu_ctrl and the legacy (START_IN_MENU = 0) size, which is used if 2..20 and otherwise defaults to 10.
  - `n_cells = active_game_cfg[4:0]`.
  - HIGH update gated by `!active_game_cfg[9]`.
  - Remove `TEST_N_CELLS`.
  - Restitution slice is `[6:5]`, rotation is `[8:7]`. Update the header comment.
- `rtl/oled_status_text.v`:
  - Stage text: `STAGE 1 EASY`, `STAGE 2 MEDIUM`, `STAGE 3 HARD`, or `CUSTOM N=17` when custom.
  - The instruction text "SW0: 90 DEG SNAP" becomes "SW15: 90DEG SNAP".
  - Input widens to 10 bits.
- `rtl/game_timer.v`: replace the exact-N case with a 32-entry table built from a constant function.
  - N = 5/10/15/20 use EASY/HARD/HUGE/XL_SECONDS.
  - Other N use `SECONDS_PER_CELL * N` (new parameter, default 12).
- `rtl/maze_gen.v` (lines 241–246):
  - `loop_cap = (n < 8) ? 0 : n / 3`. This gives 3/5/6 at N = 10/15/20, as today. N < 8 must stay 0, because `rand_col` can exceed nm1 below 8 (line 136).
  - `box_target = n <= 5 ? 0 : n < 15 ? 4 : 6`. Box quadrants need N ≥ 4 (line 166).
- `rtl/game_status_hud.v:84`: change `n_cells != 5` to `n_cells > 5`, matching the box rule.
- `rtl/item_ctrl.v:73` and `rtl/render.v:256`: the buff split at `n >= 15` already matches. No change.
- `rtl/camera.v`: uses `n_cells >= FOLLOW_MIN_N`, so it is already general.
- `scripts/build_bitstream.tcl:23-27`: remove the `TEST_N_CELLS` hook.
- `docs/parallel-workstreams.md:76-77`: update the switch lines.
- Benches:
  - `16'h0020` becomes `16'h4000`.
  - `sw[0]` becomes `sw[15]` (tb_top_rotation, tb_top_story82_countdown, tb_top_story94_invert, tb_switch_mapping).
  - `sw[5]` becomes `sw[14]`.
  - tb_top_story73_camera `16'h003E` becomes `16'h400F`.
  - Update menu text and cfg widths in tb_menu_ctrl, tb_oled_status_text, tb_game_ctrl, tb_game_state_encoding and the top story 4.x / 6.2 / 7.4 benches.
  - tb_top_n20 drops TEST_N_CELLS and reaches N = 20 through CUSTOM.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/menu_ctrl.v`: four entries, custom size, error page, 10-bit cfg.
- [x] `rtl/game_ctrl.v`: widen the cfg to 10 bits.
- [x] `rtl/My_Top_Module.v`: switch remap and sync, cfg slices, HIGH gate, remove TEST_N_CELLS, `MENU_ERROR_CYCLES` parameter (200,000,000).
- [x] `rtl/oled_status_text.v`: stage names, custom text, SW15 instruction.
- [x] `rtl/game_timer.v`: per-N limit table.
- [x] `rtl/maze_gen.v`: loop and box formulas.
- [x] `rtl/game_status_hud.v`: item row for N > 5.
- [x] `scripts/build_bitstream.tcl`, `docs/parallel-workstreams.md`: remove the hook and update the docs.
- [x] `tb/tb_menu_ctrl.v`: test the four entries, wrap, live CUSTOM value, invalid 0/1/21/31 (error, then menu, no start), and valid 2/20 start with the right cfg.
- [x] `tb/tb_custom_stage.v` (new, in run_n20.tcl):
  - maze_gen for every N = 2..20: connected, start/goal floor, the expected box and loop count, boxes inside the maze.
  - game_timer limit for every N.
- [x] `tb/tb_top_n20.v`: reach N = 20 through CUSTOM. Check that a mid-game switch change has no effect and HIGH is untouched.
- [x] Legacy benches: switch, text and width edits as in the Code Map.

**Acceptance Criteria:**
- Given the board build, when synthesised and routed, then timing is met with no new critical warnings.
- Given the full bench set, when run, then results match the PR #94 baseline (same pass/fail per bench).

## Design Notes

Placeholder per-size values (DY to playtest):

| N | Time | Boxes | Loops | Bounce |
|---|---|---|---|---|
| 2–4 | 12 s × N | 0 | 0 | 0.5 |
| 5 | 60 s | 0 | 0 | 0.5 |
| 6–7 | 12 s × N | 4 | 0 | 0.75 |
| 8–14 | 12 s × N (10 → 120 s) | 4 | N / 3 | 0.75 |
| 15–20 | 12 s × N (15 → 180, 20 → 240) | 6 | N / 3 | 0.75 |

Other decisions:
- Menu lines use aligned columns: `>EASY   HIGH=3`, ` MEDIUM HIGH=12`, ` HARD   HIGH=0`, ` CUSTOM N=17`.
- The play screen's first line for a custom game is `CUSTOM N=17`.
- The top-level parameter names `HARD_TIME_SECONDS` (N = 10) and `HUGE_TIME_SECONDS` (N = 15) stay as they are, with a comment, because benches override them.

## Verification

**Commands:**
- `vivado -mode batch -source tb/run_n20.tcl`: expected `PASS N=20 focused regression`.
- Full bench runner (C:/tr/all.tcl) on the base and the branch: expected the same per-bench results.
- `scripts/build_bitstream.tcl`, then check_timing: expected WNS ≥ 0 and WHS ≥ 0.

## Implementation Notes

- Implemented in-session (DY has not asked for subagents).
- menu_ctrl:
  - The error flag and the live CUSTOM digits are registered.
  - The first routed build failed timing (WNS −0.490 ns, 143 endpoints) on error_count != 0 → status-text mux → OLED mailbox compare, 23 levels.
  - After the fix: WNS +0.039 ns, WHS +0.045 ns. The worst path is again the pre-existing VGA menu font ROM path.
- Placed utilization (normal build, 20261104-021629): LUT 6,388, FF 7,142, BRAM 3.5, DSP 6. PR #94: LUT 6,165, FF 6,882. The only critical warning is the existing `create_generated_clock` at basys3.xdc:103, also present in both PR #94 builds.
- tb_maze_gen_golden:
  - N = 4 (no boxes now) and N = 8, 9, 11..14 (loops now) differ from main on purpose. Those sizes are skipped; tb_custom_stage checks their structure.
  - N = 2, 3, 5, 6, 7, 10, 15 still match main 3fdc74d bit for bit.
- Matrix audit:
  - Preset start and HIGH update: tb_top_n20 (EASY win sets HIGH=1), tb_menu_ctrl cfg, golden presets.
  - Custom N = 20: tb_top_n20.
  - Custom small: tb_custom_stage (N = 2..20 structure and time) and tb_top_n20 (CUSTOM N = 2 at 0:24, no boxes, WIN, no HIGH).
  - Custom N = 5 equals the EASY size and still leaves HIGH unchanged.
  - Invalid size: tb_menu_ctrl (0, 1, 21, 25, 31; error page, buttons ignored, no start).
  - Switches mid-game: tb_top_n20 (PLAY and next level).
  - Snap and seed: tb_switch_mapping (SW0/SW5 no longer act, SW15 snap reaches 90°), tb_top_rotation, tb_top_story94_invert (SW15).
- Regression (C:/tr/all.tcl, same 50 benches as PR #94):
  - Every bench has the same PASS/FAIL as the PR #94 baseline, except tb_menu_ctrl, which goes from FAIL to PASS.
  - tb_top_story62_reset first failed on its old "L=SET" byte check. It now checks ">E" and passes.
  - Stale benches whose first FAIL text changed only by name or width: tb_top_story74_stage, tb_top_story44_integration, tb_switch_mapping.
  - tb_maze_gen and tb_top_story14_integration show the same first FAIL as the baseline after their loop rule and SW4..SW0 size were updated.

## Spec Change Log

## Review Triage Log

DY has not asked for subagents, so the three review layers ran in this session on the diff since 0972013 (rtl, tb, docs, scripts).

| # | Layer | Finding | Verdict | Evidence | Route |
|---|---|---|---|---|---|
| 1 | verification-gap | The top-level slices `active_game_cfg[8:7]` (rotation) and `[6:5]` (bounce) are checked only by benches that already fail before reaching those checks (story42/43/74). | medium | The grep of `rot_speed_sel`/`restitution_sel` in tb/ finds only stale benches. | patch: tb_top_n20 sets FAST in settings and checks `angle_i.rot_speed_sel` and `ball_i.restitution_sel` at N = 20, 5 and 2. |
| 2 | verification-gap | BTNR gating during the error page (`btnR_menu_press && !menu_error`) is untested. | low | tb_menu_ctrl has no BTNR. | patch: tb_top_n20 presses BTNR during the N = 25 error. |
| 3 | verification-gap | The HUD change `n_cells > 5` is not covered by a passing bench. | low | The HUD is checked only in stale story 9.2/9.5 benches. | patch: tb_top_n20 checks `hud_i.item_row_active` at N = 20 and at N ≤ 5. |
| 4 | blind | docs/parallel-workstreams.md still lists `n_cells[3:0]` at two inputs. | low | Lines 56 and 183. | patch: changed to `[4:0]`. |
| 5 | edge-case | Legacy START_IN_MENU = 0 builds credit every win to the EASY HIGH, because `active_game_cfg` stays N = 5 while N comes from the switches. | low | The same was true before (cfg[3:0] = 5). Debug-only build. | reject: pre-existing, not reachable on the board build. |
| 6 | edge-case | `ERROR_HOLD_CYCLES = 0` would load −1 and hold the error for 2^W cycles. | low | Parameter misuse only; default is 200,000,000. | reject. |
| 7 | blind | The CUSTOM row digits lag `custom_n` by one clock (registered for timing). | low | 10 ns on a human-set switch. | reject. |
| 8 | edge-case | Changing SW4..SW0 between the BTNC press and the frame boundary could start a size that was not validated. | false | game_ctrl latches `game_cfg` into `start_cfg_pending` on the same cycle as the `start_game` pulse that menu_ctrl validated. | reject. |
| 9 | edge-case | For N = 8 or 9, `rand_col` could exceed `nm1` and place a loop outside the maze. | false | With non-wide `rand_src` 0..15 and N ≥ 8, `rand_src − n < n`. tb_custom_stage checks walls outside the map for N = 2..20. | reject. |
| 10 | edge-case | The timer table entries for N = 21..31 are unchecked. | false | No path loads them: menu_ctrl rejects 21..31, the legacy fallback is 10 and the backdrop is 15. | reject. |
| 11 | blind | The skip list in tb_maze_gen_golden duplicates the RTL rule. | low | Intentional pin of which sizes still match main. | reject. |
| 12 | blind | tb_switch_mapping seed checks still fail. | low | They fail the same way on main 3fdc74d. Already in deferred-work.md (17 stale benches). | reject: pre-existing, logged. |
| 13 | edge-case | The OLED instruction pages do not mention SW4..SW0 (custom size) or SW14 (fixed seed). | low | Players learn the size switches only from the error page. Not requested. | defer |
