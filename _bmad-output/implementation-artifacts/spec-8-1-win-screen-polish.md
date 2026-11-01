---
title: 'Story 8.1: Win screen polish'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_commit: '5f89f1bcb9be69c035a469c174c84550513fe6e7'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The WIN screen is a plain YOU WIN panel. It does not tell the player their time, and the goal tile they just reached looks the same as during play.

**Approach:** In WIN, the goal tile blinks at about 2 Hz and the panel gains a second line with the timer as `mm:ss`, taken from `game_timer`. Both change only at the frame boundary, so the picture never tears or flickers.

## Boundaries & Constraints

**Always:**
- The time shown is `game_timer`'s BCD minutes and seconds, latched in `render` at `frame_tick_d[1]` with the existing WIN snapshot.
- The blink phase advances only at that same point and restarts when WIN begins.
- The label of the second line is `TIME` (decided by the human): it reads right while the timer counts up and still reads right after Story 8.2 makes it a countdown.
- The title text and the x/y position of `YOU WIN` stay where they are (156..483, 212..267).
- Single writer: `render` and `win_overlay` only; `game_timer` and `game_ctrl` are not touched.
- Timing stays met and no DSP or block RAM is added.

**Never:**
- No change to PLAY, MENU or GENERATE pictures.
- No change to `game_timer` behaviour (count-down is Story 8.2).
- No new font data; use `font_rom`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Win with time | WIN, timer 01:23 | Panel line reads `TIME 01:23` in white on the panel | N/A |
| Blink | WIN frames 0..15 / 16..31 | Goal tile bright green / dark green, repeating | N/A |
| WIN begins | state changes to WIN on a frame boundary | Time, panel and blink phase 0 appear together on that frame | N/A |
| Timer saturated | timer 99:59 | `TIME 99:59` | N/A |
| Leaving WIN | state not WIN | No panel, no blink, normal goal colour | Phase counter cleared |
| Reset in WIN | rst | Picture back to blank, phase cleared | N/A |

</frozen-after-approval>

## Code Map

- `rtl/win_overlay.v` -- fixed panel and `YOU WIN` text via `font_rom`; panel is 132..507 x 192..287 with a 4 px rim. Add the second text band and extend the panel.
- `rtl/render.v` -- already latches `win_frame` at `frame_tick_d[1]`; instantiates `win_overlay`; goal colour comes from `is_goal_d`. Add the latched time, the blink phase and the goal colour choice.
- `rtl/My_Top_Module.v` -- instantiates `render_i`; wires `elapsed_minutes_bcd` / `elapsed_seconds_bcd` (already present for the OLED).
- `rtl/game_timer.v` -- source of the BCD time; read only.
- `tb/tb_win_render.v` -- raster-level model of the panel; update bounds, add the time line and blink checks.
- `tb/tb_rotated_render.v` -- instantiates `render`; add the new ports.
- `tb/tb_top_win_indication.v` -- pixel (156,212) checks; must still pass unchanged.
- `tb/run_current_stories.tcl` -- bench list; no new bench file expected.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/win_overlay.v` -- add inputs for the four BCD digits; draw `TIME mm:ss` at 4x scale in a 320 x 28 px band at x 160..479, y 284..311; extend the panel and its rim down to y 324 -- the new line needs room; keep one shared `font_rom`
- [x] `rtl/render.v` -- add `time_min_bcd`, `time_sec_bcd` inputs; latch them with `win_frame`; add a blink phase that toggles every `BLINK_FRAMES` (default 16) captured frames in WIN and clears outside WIN; draw a dark-green goal tile when `win_frame` and the phase is set
- [x] `rtl/My_Top_Module.v` -- connect the elapsed BCD wires to `render_i`
- [x] `tb/tb_win_render.v` -- update the model for the new panel bounds and time line (digits from a row-bitmap model), check the blink phase over several frames, the latching (no change mid-frame) and the reset
- [x] `tb/tb_rotated_render.v` -- tie the new ports
- [x] `tb/run_current_stories.tcl` -- no change unless a bench is added; confirm the whole regression passes

**Acceptance Criteria:**
- Given WIN, when the picture is drawn, then the goal tile blinks at a few Hz and the panel shows the time as `mm:ss`.
- Given `tb_win_render` at known frames, when it runs, then the time glyphs and the blink phase match the model.
- Given the existing benches, when the regression runs, then they pass unchanged (apart from the new ports).
- Given the routed build, when it completes, then timing is met.
- Given the board, when a game is won, then the time on the panel matches the OLED and the blink does not flicker (checked by someone other than the author).

## Implementation Notes

- Implemented directly (no implementation subagent). Files: `rtl/win_overlay.v`, `rtl/render.v`, `rtl/My_Top_Module.v`, `tb/tb_win_render.v`, `tb/tb_rotated_render.v`. `tb/run_current_stories.tcl` needed no change: `tb_win_render` is already in it.
- Decided: label `TIME`; goal dark phase is (0,3,0); `BLINK_FRAMES` is a `render` parameter (16 by default, 3 in the bench).
- Verification (Vivado 2025.2, run from the scratchpad, 2026-10-31): `tb_win_render`, `tb_rotated_render`, `tb_render` and `tb_top_win_indication` pass; the full `run_current_stories.tcl` regression passes. Breaking the time digit and the blink on purpose made `tb_win_render` print FAIL lines, so those checks are live.
- Routed build (no bitstream): synthesis 0 errors and 0 critical warnings; WNS +0.323 ns, WHS +0.099 ns, all constraints met. 2,957 LUTs (+46 vs Story 4.4), 2,601 registers (+25), 1.5 BRAM tiles, 6 DSPs (unchanged).
- Not done: the Basys 3 board check (needs someone other than the author). The independent review layers were not run (no subagents were requested); the review below is the author's own pass over the diff.

## Spec Change Log

## Review Triage Log

| Finding | Verdict | Evidence |
|---|---|---|
| `blink_count` is 8 bits; `BLINK_FRAMES` above 256 would never wrap | low | Default is 16 and the parameter is not overridden in the top; negligible, left as is |
| BCD digits above 9 would draw `:` to `?` | false | `game_timer` only produces valid BCD (its bench checks this) |
| Time text near the title could clash | false | Title ends at y=267, time starts at y=284; `time_sel` switches at y=276 and the raster test checks every pixel |
| Goal tile could be hidden by the panel | low | At some angles the panel covers it; the blink still shows when it does not. Not a defect of this story |
| Timing regression from the extra mux | false | Routed WNS +0.323 ns, WHS +0.099 ns |

## Design Notes

The title stays untouched so `tb_top_win_indication` (which probes pixel 156,212) keeps its meaning. The time band is the 10 cells `T I M E _ m m : s s`, each 32 px wide (a 5-column glyph at 4x scale plus blank), so the cell index is a shift. Until Story 8.2 the number is the elapsed time; the same wiring shows the time left afterwards.

## Verification

**Commands:**
- `tb/run_current_stories.tcl` with Vivado Simulator 2025.2, run from the scratchpad (not the repo) -- expected: `PASS: win render ...` and `PASS regression ...`
- `scripts/check_timing.tcl` -- expected: setup and hold met

**Manual checks (if no CLI):**
- On the Basys 3, win a game: the goal blinks about twice a second without flicker and the panel time equals the OLED time.
