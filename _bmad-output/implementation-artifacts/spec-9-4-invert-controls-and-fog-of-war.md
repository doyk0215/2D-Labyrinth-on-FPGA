---
title: 'Story 9.4: Invert controls and fog of war'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_commit: 'a26d9d895c8770e8a629bb0435d633f1c757b5ed'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 9.2 can roll the INVERT and FOG debuffs, but neither does anything yet, so two of the five debuff boxes carry no risk.

**Approach:** While `item_ctrl`'s active effect is INVERT, the top level flips the sign of the rotation command, so left turns right and right turns left. While it is FOG, `render` blanks every pixel farther than a radius from the ball on screen.

**Decisions (DY, 2026-11-02):** DY writes all of 9.4, including invert controls, which issue #64 gave to CJX; CJX reviews the invert part. The fog radius is 48 px (three tiles), a parameter that 9.8 tunes. Fog hides everything except the ball: map, start, goal, boxes and backdrop outside the circle are blank; the ball always shows.

**Decision (DY, 2026-11-02, after review):** to meet routed timing, the item seconds' tens/units split in `oled_status_text` (CJX's file) becomes a lookup table instead of `/10` and `%10`; the OLED text is identical. CJX reviews that part. The top's OLED mailbox stays as on main, so it does not conflict with PR #85 (9.7).

## Boundaries & Constraints

**Always:**
- Invert applies to the mouse and the board buttons, in smooth and snap modes, and ends when the effect ends. The invert is a sign flip of `angle_rot_cmd` (CW and CCW swap; no command and both buttons stay zero).
- Fog is in screen space, centred on the ball's screen position. A pixel is clear when dx^2 + dy^2 <= R^2 (dx, dy from the ball centre). Blank means black (0x000). The ball is drawn as usual, even at the fog edge.
- `render` latches the fog on/off flag with its other per-frame snapshot in vertical blanking, so a picture is never half fogged.
- The fog test lines up with `ball_on` (one clock after `pixel_x`/`pixel_y`) and uses no DSP.

**Never:**
- No change to `item_ctrl`, effect codes, durations, the OLED text or its handoff, physics or the other effects (9.3, 9.5, 9.7). No change to WIN/LOSE panels.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Invert, smooth | INVERT active, right held | angle decreases (as left does normally) | N/A |
| Invert, snap | INVERT active, right press/release | angle steps 90 degrees counter-clockwise | N/A |
| Invert ends | effect becomes NONE | directions return to normal | N/A |
| Snap press held as invert starts or ends | direction flips mid-press | that press is cancelled (no step), as for an opposite press | N/A |
| Fog, inside | FOG active, d^2 <= R^2 | pixel identical to the unfogged picture | N/A |
| Fog, outside | FOG active, d^2 > R^2 | black, unless it is a ball pixel | N/A |
| Fog starts/ends mid-frame | effect changes during scan-out | that frame keeps its fog state; the next frame changes | N/A |
| No fog | any other effect or NONE | picture unchanged | N/A |

</frozen-after-approval>

## Code Map

- `rtl/My_Top_Module.v:287-291` -- `angle_rot_cmd`; negate its final value when `item_effect == ITEM_INVERT`. Covers smooth (`rot_cmd` from `input_mux`) and snap (`snap_left`/`snap_right`) paths, mouse and buttons. Add `FOG_RADIUS_PX` parameter (48); pass the fog flag and `fog_clear` to `render`.
- `rtl/angle_accumulator.v:85-92` -- snap press logic; a direction change mid-press already cancels. Do not change.
- `rtl/ball_overlay.v:94-104` -- reuses `dx`, `dy`, `adx`, `ady`; add parameter `FOG_RADIUS` and a registered `fog_clear` output beside `ball_on`: bounding test `adx, ady <= R` then LUT squares (`use_dsp = "no"`) and compare to R^2.
- `rtl/render.v:128-160, 270-305` -- add inputs `fog_en`, `fog_clear`; latch `fog_frame <= fog_en` at `frame_tick_d[1]` with `win_frame`; clear on reset. In the colour mux, after `ball_on` and before the map: `fog_frame && !fog_clear` gives black.
- `rtl/labyrinth_pkg.vh` -- `ITEM_INVERT`, `ITEM_FOG` already defined. Do not change.
- `rtl/oled_status_text.v:73` -- item seconds `digit_ascii(effect_seconds/10)`, `%10`; replace with a 0..127 digit table giving the same tens/units (decision above). Covered by `tb_oled_status_text` item rows.
- Benches instantiating `render` or `ball_overlay` directly: `tb_rotated_render`, `tb_story71_map`, `tb_story73_render`, `tb_win_render`, `tb_lose_render`, `tb_game_state_encoding`, `tb_ball_overlay` -- tie `fog_en`/`fog_clear` off.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/ball_overlay.v` -- `FOG_RADIUS` parameter and `fog_clear` -- the fog circle test
- [x] `rtl/render.v` -- `fog_en`, `fog_clear`, frame latch and blanking -- the fog picture
- [x] `rtl/My_Top_Module.v` -- invert sign flip, `FOG_RADIUS_PX`, wiring -- both effects reach the hardware
- [x] `tb/tb_fog_render.v` (new) -- `ball_overlay` plus two `render` instances (fog on, fog off as reference) on a fixed map; every pixel of a frame at 0 and 45 degrees: inside the circle equals the reference, outside is black unless ball; fog flag changed mid-frame takes effect only next frame; independent integer distance model -- the fog edge check the AC asks for
- [x] `tb/tb_top_story94_invert.v` (new) -- real top; force `item_i.active_effect`; buttons and mouse, smooth and snap, normal vs inverted direction, and back to normal on NONE -- the invert AC
- [x] direct `render`/`ball_overlay` benches above -- tie-offs -- keep them compiling
- [x] `tb/run_current_stories.tcl`, `tb/run_story94.tcl` (new) -- add the two benches -- regression
- [x] `docs/parallel-workstreams.md` -- 9.4 interface notes -- record fog/invert contract
- [x] Story file `_bmad-output/implementation-artifacts/9-4-invert-controls-and-fog-of-war.md` -- results -- issue workflow

**Acceptance Criteria:**
- Given the full regression and the routed build, when run, then everything passes, timing is met at 100 MHz and the AD-8 caps hold (no new DSP).

## Implementation Notes

- Implemented directly (DY asked for no implementation subagent).
- `tb_fog_render` checks three whole frames (0 degrees, 45 degrees with the ball on a box, and a circle clipped by the top-left of the screen), plus fog-off and mid-frame on/off lines: 965,120 pixels, of which 709 lie just inside and 753 just outside the circle's edge. The ball's screen position is read from `ball_overlay`, and the distance model is integer arithmetic in the bench.
- `tb_top_story94_invert` forces `item_i.active_effect`; it does not roll INVERT through a pickup (pickup-to-effect wiring is covered by `tb_top_story92_items`).
- First run of the invert bench failed on its own bug: `force x = level` keeps `x` tied to the task's shared argument, so a mouse button followed later calls. The forces now use constants.
- Mutants: removing the invert sign flip fails `tb_top_story94_invert`; `fog_d2 < FR2` instead of `<=` fails `tb_fog_render` at a pixel exactly 48 px from the ball.
- The first routed build failed setup timing (WNS -0.128 ns, 14 endpoints). The failing path was not new logic: Story 9.2's item-seconds `/10`/`%10` in `oled_status_text`, then the top's 512-bit status compare into `text_mailbox` (20 levels). A first fix registered `status_text` in the top before the mailbox (+0.468 ns), but PR #85 (9.7) changes the same mailbox lines and adds an unregistered roulette visual to the same transfer, so the two would conflict and the text would lag the visual by a clock. DY chose instead to replace `/10`/`%10` with a 128-entry digit table in `oled_status_text`; the top mailbox is back to main. (That register version also showed a simulation-only X trap: loading the registered text during reset left X in the mailbox and failed `tb_top_story44_integration`.)
- Matrix audit added two invert-bench checks: a snap press held while the effect starts is cancelled, and only FOG drives `render.fog_en`.

## Spec Change Log

- Review pass 1, finding "OLED register contradicts the frozen Never (no OLED change)" (blind and edge-case layers). DY amended the intent: the seconds split in `oled_status_text` becomes a lookup table with identical text; the Never now reads "the OLED text or its handoff". Known-bad state avoided: a top-level register on the OLED mailbox that conflicts with PR #85 and misaligns text and roulette visual. KEEP: invert sign flip, `fog_clear` in `ball_overlay`, fog latch and mux in `render`, both new benches.

## Review Triage Log

| Finding | Verdict | Evidence | Route |
|---|---|---|---|
| No top-level check of the fog wiring (`fog_clear` and `fog_en` into `render`, pixels at the VGA pins) (verification-gap; blind: invert bench's fog check stops at a wire) | medium | `tb_fog_render` wires its own instances; `tb_top_story94_invert` only checked `render_i.fog_en`; dropping `.fog_clear` would pass every bench | patch: invert bench checks a fogged and a clear pixel at the top's RGB after the frame latch |
| Top OLED register contradicts the frozen "no change to the OLED" (edge-case claim; blind) | medium | real; also conflicts with PR #85's mailbox change | intent: DY chose the digit table in `oled_status_text`; register removed (Spec Change Log) |
| Register costs 512 flip-flops and leaves the reset-mux path (blind) | false | synthesis kept 174 flip-flops; register now removed | reject |
| `tb_fog_render` failure reason `[255:0]` truncates messages (edge-case) | low | messages are 35-38 characters | patch: `[511:0]` |
| `FOG_RADIUS` has no range check (edge-case; blind) | low | only set by the top parameter, 48; out-of-range values are not a realistic tuning choice | reject |
| `run_story94.tcl` accepts any "PASS" for `tb_ball_overlay` (blind) | low | direct correction | patch: marker "PASS: ball_overlay" |
| `run_story94.tcl` omits the tie-off benches, 4.4 and 9.2 (blind) | low | all run in `run_current_stories.tcl` | reject |
| No unit test of `fog_clear` width boundaries / large radius (blind) | low | generic width code; only the default radius ships, 9.8 reruns `tb_fog_render` if it changes | reject |
| Ball-over-fog order never exercised because the ball is always inside R = 48 (blind) | low | unreachable while FOG_RADIUS > BALL_RADIUS (48 vs 5) | reject |
| `tb_fog_render` takes the ball position from the DUT (blind) | false | the bench checks the fog circle; ball position at every angle is checked by `tb_ball_overlay` | reject |
| Coverage failure message prints counts in the pixel slot and omits three counters (blind) | low | direct correction | patch: print all counters |
| Invert not tested in WIN/LOSE/MENU (blind) | false | `rot_cmd_normal` is already 0 there and -0 = 0; `item_ctrl` also clears the effect outside PLAY | reject |
| Epic note "fog radius depends on the final map size" (blind) | false | that is what the planning backlog says (order-of-work note) | reject |
| Doc says `active_effect` while the top tests `item_effect`; "constant-size squares" comment; "two 6-bit squares" only at the default radius (blind) | low | wording | patch: wording |
| New deferred-work entry lacks owner/target (blind) | false | entry removed: the divider is now fixed in this story | reject |
| Story file placeholders and no routed result recorded (blind; verification-gap other) | false | filled in from the final runs before commit | reject |

## Design Notes

R = 48 needs 6-bit squares (48^2 = 2304): two LUT squares, an add and a compare per pixel, registered once like `ball_on`. Black (not the 0x002 backdrop) makes the fog edge visible against the dark-blue surround.

## Verification

**Commands:**
- `vivado -mode batch -source tb/run_story94.tcl` (short C:\ folder) -- expected: both PASS
- `vivado -mode batch -source tb/run_current_stories.tcl` -- expected: all PASS
- `vivado -mode batch -source scripts/check_timing.tcl` (TEMP short) -- expected: timing met, DSPs still 6
