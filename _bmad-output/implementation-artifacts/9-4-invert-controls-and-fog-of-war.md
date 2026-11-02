---
story_id: 9.4
story_key: 9-4-invert-controls-and-fog-of-war
title: Invert controls and fog of war
status: review
owner: DY
epic: 9
depends_on: [9.2]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/64
---

# Story 9.4: Invert controls and fog of war

The INVERT and FOG debuffs from Story 9.2 now act. Spec:
[spec-9-4-invert-controls-and-fog-of-war.md](spec-9-4-invert-controls-and-fog-of-war.md).

DY wrote all of 9.4, including invert controls, which issue #64 gave to CJX
(decided by DY on 2026-11-02); CJX reviews the invert part.

## Implementation

- Invert controls: while `item_ctrl`'s active effect is INVERT, the top
  negates the rotation command, so left and right swap for the mouse and the
  board buttons, in smooth and snap modes. It ends with the effect. A snap
  press held while the effect starts or ends changes direction, so
  `angle_accumulator` cancels that press, as it does for an opposite press.
- Fog of war: `ball_overlay` has a second circle test, `fog_clear`, of radius
  `FOG_RADIUS` (48 px by default, the top's `FOG_RADIUS_PX` parameter) around
  the ball's screen centre. It uses a bounding-box test and two 6-bit squares
  in LUTs, registered with `ball_on`. While the effect is FOG, `render` draws
  every pixel outside that circle black, except the ball: map, start, goal,
  boxes and backdrop. The fog flag is latched with the frame snapshot, so a
  picture is never half fogged.
- Timing: the first routed build failed setup (WNS -0.128 ns) on Story 9.2's
  item-seconds `/10` and `%10` in `oled_status_text`, feeding the top's OLED
  text compare. DY chose to replace them with a 0..127 digit lookup table in
  `oled_status_text` (CJX's file, same text; CJX reviews this part). The top's
  OLED mailbox is unchanged from main.
- No change to `item_ctrl`, effect codes, durations, physics or OLED text.

## Simulation (Vivado 2025.2)

- `tb_fog_render`: PASS. Two renderers, one fogged and one not, on a fixed
  map with boxes; every pixel of three whole frames (0 degrees, 45 degrees
  with the ball on a box, and a circle clipped by the screen corner) against
  an integer distance model: inside the circle equals the unfogged picture,
  outside is black. 965,120 pixels, 709 just inside and 753 just outside the
  edge. Fog switched on or off mid-frame changes only the next frame.
- `tb_top_story94_invert`: PASS. Real top, effect forced through `item_ctrl`:
  board and mouse buttons, snap and smooth, swap direction under INVERT and
  return to normal after it; a snap press held while the effect starts or
  ends is cancelled; both buttons still hold; FOG does not invert. Only FOG
  drives `render.fog_en`, and at render's output a pixel 120 px from the ball
  is black while one 20 px away is not.
- `tb_oled_status_text`: PASS, now with every item seconds value 1..99.
- Mutants caught: removing the invert, `<` instead of `<=` at the fog edge
  (fails exactly 48 px from the ball), and `render.fog_clear` left unconnected
  in the top.
- The benches that instantiate `render` directly tie the fog inputs off.
- `tb/run_current_stories.tcl`: PASS, exit code 0, 48 PASS lines.

## Routed build

`scripts/check_timing.tcl` (100 MHz): timing met. WNS +0.220 ns (main
+0.369 ns), WHS +0.024 ns. 4,319 LUTs (main 4,291), 4,351 registers (main
4,343), 3 block RAM tiles, 6 DSPs: 20.8% of LUTs, 10.5% of flip-flops, 3 of 6
block RAM tiles and 6 of 8 DSPs, within the AD-8 caps. The worst path is the
existing OLED text compare (`item_i/active_effect` through the effect-name
selection and the 512-bit compare into `text_mailbox`, 21 levels), not 9.4
logic. PR #85 (9.7) adds its roulette visual to that compare, so it should
check this path.

## Review and board check

Three review subagents (blind, edge-case and verification-gap) read the diff.
Findings and verdicts are in the spec's Review Triage Log. Fixes: a top-level
fog pixel check, the digit table replacing the first (register) timing fix,
bench message and marker fixes, and wording. Nothing was deferred.

The board check is not done. It needs a teammate other than DY.
