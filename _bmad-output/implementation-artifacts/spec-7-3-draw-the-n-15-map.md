---
title: 'Story 7.3: Draw the N = 15 map'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '9c2be2137b0a9e97e72a75a858d97f54573ddfe7'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The N = 15 map is 496 px square, so with today's fixed view, centred on the map, it does not fit the 480-line screen at most angles. Story 7.2's camera says where to look, but nothing uses it yet.

**Approach:** `render` centres the view on map centre + camera instead of the map centre, and `ball_overlay` draws `ball - cam`. Both use the same camera value, which changes only in vertical blanking. On N = 5 and N = 10 the camera is (0, 0), so their picture does not change.

## Boundaries & Constraints

**Always:**
- The per-frame part of the scanline start (map centre + `cam << 6` - 320 x cos or sin) is a register, so the per-scanline adder is no deeper than today.
- `ball_overlay` starts on `cam_done` rather than `phys_done`, so it uses this frame's camera (it moves two clocks after `phys_done`) and also runs after the snap on `phys_init`. It registers `ball - cam` before its products; the rotation and the DSP count do not change.
- `render` takes `cam_x`/`cam_y` live: the camera changes only inside vertical blanking, after the sin/cos snapshot.
- Pixels outside the active map show the background (already true since 7.1).
- Timing stays met; no DSP or block RAM is added.

**Never:**
- No change to `camera`, `ball_physics` or the package.
- No N = 15 menu entry (Story 7.4).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fixed stage | N = 5 or 10, cam (0, 0) | Picture identical to today | N/A |
| Camera near a map edge | N = 15, cam about 200 px from the centre on one or both axes | The map edge and the background beyond it are drawn where the model says | N/A |
| Rotated | 0, 45, 90, 135 degrees with a camera offset | Each pixel matches the inverse-map model | N/A |
| Ball through the camera | N = 15, ball moving | Drawn ball centre = rotation of `ball - cam` about the screen centre, within 1 px | N/A |
| Snap | `phys_init` | First PLAY frame shows the ball at the screen centre | N/A |
| No tearing | active video | `cam_x`, `cam_y`, the scanline base and the ball's screen position do not change | N/A |

</frozen-after-approval>

## Code Map

- `rtl/render.v` -- `active_centre_q` (map centre, Q13.14) feeds `line_x_q`/`line_y_q` with the `-320 x cos/sin` term; replace with registered `base_x_q`/`base_y_q` = centre + `cam << 6` - 320 x cos/sin; add `cam_x`, `cam_y` inputs. `in_map_now` bounds and `{row, col}` address stay.
- `rtl/ball_overlay.v` -- 3-stage position pipeline on `start`; add `cam_x`, `cam_y` and a first stage `rel = ball - cam`.
- `rtl/camera.v` -- read only; `cam_done` is two clocks after `phys_done` and one after `phys_init`.
- `rtl/My_Top_Module.v` -- `camera_i` exists with unused outputs; wire them to `render_i` and `ball_ov_i`, and drive `ball_ov_i.start` from `cam_done`.
- `tb/tb_render.v`, `tb/tb_rotated_render.v`, `tb/tb_story71_map.v`, `tb/tb_win_render.v`, `tb/tb_game_state_encoding.v` -- instantiate `render`; tie the camera to 0, expectations unchanged.
- `tb/tb_ball_overlay.v` -- tie the camera to 0; it waits 6 clocks after `start`, enough for one more stage.
- `tb/tb_rotated_render.v` -- reference for the real-number inverse-map model and the edge-sample rule.
- `tb/tb_top_ball.v` -- reference for measuring the drawn ball in the VGA stream; it runs N = 10 and must pass unchanged.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/render.v` -- add the camera inputs and the registered per-frame base -- the view follows the camera without a deeper scanline path
- [x] `rtl/ball_overlay.v` -- add the camera inputs and the `ball - cam` stage -- the ball is drawn relative to the view centre
- [x] `rtl/My_Top_Module.v` -- connect the camera; overlay starts on `cam_done`
- [x] `tb/tb_story73_render.v` (new) -- N = 15 raster against the real-number model at 0, 45, 90 and 135 degrees for camera (0, 0) and positions near each map edge, with its own pseudo-random 32 x 32 tile RAM; outside-map pixels are background
- [x] `tb/tb_top_story73_camera.v` (new) -- legacy top at N = 15 (`sw[4:1]` = 15): the drawn ball matches the rotation of `ball - cam` within 1 px over several frames, while falling and while rotating; the first PLAY frame shows it at the screen centre; the camera, the scanline base and the ball's screen position never change in active video; the maze coordinate under the drawn ball equals the ball position
- [x] existing benches -- add the camera ports tied to 0; `tb/run_current_stories.tcl` -- add both new benches

**Acceptance Criteria:**
- Given an N = 15 maze and a set of camera positions including near each map edge, when it is rendered at 0, 45, 90 and 135 degrees, then the raster bench matches the software model and pixels outside the map show the background.
- Given the ball and the camera in the top-level bench, when the ball moves and bounces, then the drawn ball stays aligned with the physics position and the picture does not tear.
- Given the existing N = 5 and N = 10 stages, when the render benches run, then they pass unchanged.
- Given the routed build, when it completes, then timing is met with no added DSP.
- Given the board with a legacy build at `sw[4:1]` = 15, when a game is played, then the view follows the ball without shaking and the ball stays on screen (checked by someone other than the author).

## Implementation Notes

- Implemented directly (no implementation subagent). Files: `rtl/render.v`, `rtl/ball_overlay.v`, `rtl/My_Top_Module.v`; new `tb/tb_story73_render.v`, `tb/tb_top_story73_camera.v`; camera ports tied to 0 in `tb_rotated_render`, `tb_story71_map`, `tb_win_render`, `tb_game_state_encoding`, `tb_ball_overlay`; both new benches added to `tb/run_current_stories.tcl`; `docs/parallel-workstreams.md` records the render and camera wiring.
- `ball_overlay` widens `ball - cam` to 19 bits (and its products and sums by one bit), so it cannot wrap; the DSP count is unchanged.
- Side effect, accepted: the overlay now also runs after the snap on `phys_init`, so the first PLAY frame shows the ball on its spawn tile. Before, that one frame showed the ball where it was before the new maze (the overlay only ran on `phys_done`, which `ball_physics` skips on the `phys_init` frame). This applies to N = 5 and N = 10 too; `tb_top_ball` passes unchanged.
- `tb_top_story73_camera` forces `dut.ball_x/ball_y` for 16 frames to make the camera follow, as the natural ball stays inside the dead zone in the start cell. It runs about 8 minutes; the first version measured more frames and took 14.5.
- Mutation check: dropping `cam_x` from the base, using `cam_x` for y, or scaling it by `<<< 5` each made `tb_story73_render` fail (174,787, 135,390 and 153,891 pixel errors).
- Verification (Vivado 2025.2, from the scratchpad, 2026-11-01): full `run_current_stories.tcl` PASS (36 PASS lines, about 20 minutes). `tb_story73_render`: 183,096 pixels checked, 104,362 beyond the map. Top bench: first PLAY frame drawn at (320, 240); drawn ball within 0.4 px of the rotation of `ball - cam`; camera followed the forced path; no change in active video. Routed: WNS +1.197 ns, WHS +0.077 ns, all constraints met; 3,466 LUTs (+130 vs main), 3,650 registers (+120), 2.5 BRAM tiles, 6 DSPs (unchanged).
- Not done: board check (needs someone other than the author; N = 15 is reachable only with a legacy build, `START_IN_MENU = 0` and `sw[4:1]` = 15, until Story 7.4). The independent review layers were not run (no subagents were requested); the review below is the author's own pass.

## Review Triage Log

| Finding | Verdict | Evidence |
|---|---|---|
| The first PLAY frame now differs on N = 5 and N = 10 (ball on its spawn instead of its old place) | low | Accepted: the old frame was a one-frame glitch; recorded in the notes; `tb_top_ball` passes unchanged |
| `ball - cam` could wrap in 18 bits | false | Widened to 19 bits in `ball_overlay`, products and sums widened with it |
| The base register is recomputed every clock and has no reset | false | Its inputs (camera, trig snapshot, `n_cells`) change only in vertical blanking or at reset; the top bench saw no change in active video |
| `render` reads the camera live instead of snapshotting it | false | The camera changes only two clocks after `phys_done`, in vertical blanking after the sin/cos snapshot; a reset mid-frame clears render too |
| The regression is about 8 minutes longer | low | `tb_top_story73_camera` runs whole frames; trimmed from 14.5 minutes; kept because it is the only check of maze and ball alignment through the camera |
| The regression banner still names only Story 6.1 | low | Superseded by the independent review below: fixed

Independent review (2026-11-01; Blind Hunter, Edge Case Hunter and Verification Gap subagents on the combined 7.2 + 7.3 diff):

| Finding | Verdict | Evidence |
|---|---|---|
| Blind: the Code Map lists `tb/tb_render.v` as instantiating `render` | low | True (it instantiates the top). Rejected: the fix would edit this spec |
| Blind: the Code Map says `cam_done` is one clock after `phys_init` | low | True, it is two, like `phys_done`. Both are in vertical blanking, so nothing depends on it. Rejected: spec-only fix |
| Blind: specs say `done` while the board check is open | false | `done` ends this workflow; the board check is tracked on the PR. Rejected: spec-only fix |
| Blind: `docs/parallel-workstreams.md` still says render latches the ball at frame start (AD-6) | low | Patched: the line now records the live camera read and the overlay's `cam_done` latch |
| Blind: the render base has no load enable, so a camera change outside blanking would tear | low | With the follow latch below, the camera changes only on `cam_done` or reset, and `tb_camera` now asserts that; an enable would guard an unreachable state. Rejected |
| Blind: `tb_camera` does not check the `cam_done` latency or that the camera changes only with `cam_done` | medium | Patched: exact two-clock checks after `phys_done` and `phys_init`, and a monitor; the monitor found the live-`n_cells` change (Edge finding 1) |
| Blind: `phys_done` with or just after `phys_init` is untested | low | Patched: both cases added and pass. Removing the `!phys_init` gate changes nothing observable (the snap one clock later wins), so the gate is defensive only |
| Blind: `tb_story73_render` uses whole-pixel cameras only | medium | Patched: (-137.37, 91.5) and (180.6, -203.2) added; 244,413 pixels checked |
| Blind: `tb_camera` copies the camera parameters as literals | low | The bench fails loudly if a parameter changes. Rejected: plumbing for an unlikely edit |
| Blind: `check_on_screen` truncates to whole pixels | low | Patched: compared in Q9.8 with reals |
| Blind: the top bench's follow check only tests "changed" | medium | Patched: the forced path is x-only for 24 frames; the bench checks cam_x moved left by over 20 px, cam_y did not move, and the offset stays within 88 px |
| Blind: the top bench divides by `n_clk` before checking it | low | Patched: checks first |
| Blind: the regression banner is stale | low | Patched: names 6.1, 7.1, 7.2, 7.3 and 9.6 |
| Blind: one long comment line in `render.v` | low | Patched: re-wrapped |
| Verification gap: `ball_overlay`'s `ball - cam` is never tested with a camera whose x and y differ | medium | Patched: `tb_ball_overlay` has a camera input and five asymmetric cases; using `cam_x` for both axes, or swapping them, now gives 6 FAIL lines each |
| Edge 1: live `n_cells` (legacy switches) flips `follow` mid-game, moving the camera without `cam_done` | low | Patched: `follow` is latched on `phys_init`, one register; the camera now changes only with `cam_done` or reset |
| Edge 2 (claim): the Intent says N = 5 and N = 10 pictures "do not change", but their first PLAY frame now shows the ball on its spawn | low | True; an improvement recorded in the notes, but it differs from the frozen Intent wording. Decided by DY on 2026-11-01: keep the fix. "Does not change" means every frame after the first; the first PLAY frame now shows the ball on its spawn tile on all stages |

## Design Notes

Timing in one frame: `frame_tick` (line 480) -> sin/cos snapshot 2 clocks later -> physics -> `phys_done` -> camera and `cam_done` 2 clocks later -> overlay 4 clocks later, all well before line 524 loads the first scanline. The base register is recomputed every clock, but its inputs move only in that window, so every visible line of a frame uses one camera position.

## Verification

**Commands:**
- `tb/run_current_stories.tcl` (Vivado 2025.2, from the scratchpad) -- expected: `PASS regression`, including the two new benches
- `scripts/check_timing.tcl` with a short `TEMP` -- expected: setup and hold met, 6 DSPs
