---
title: 'Story 7.2: Camera that follows the ball'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '09f0cfebf53dad332d448764140836729c4371e1'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The N = 15 map (31 tiles x 16 px = 496 px, about 700 px across the diagonal) does not fit the 640 x 480 screen at every angle, so the view has to follow the ball. Nothing yet says where the view should be.

**Approach:** A new `camera` module (owner DY) outputs `cam_x`, `cam_y` (signed Q9.8 maze pixels from the map centre, the ball's format) once per frame on `phys_done`: a dead zone of about +/-48 px per axis around the camera's target, then `cam += (target - cam) >>> CAM_SHIFT` (about 3), shift and add only. It snaps to the ball on `phys_init` and outputs the map centre (0, 0) on the fixed stages. Story 7.3 will consume it; until then the top instantiates it with its outputs unused, so the picture does not change.

Decisions (choices the player does not see, recorded here):
- The dead-zone box is centred on the target (the camera's settled position), not on the lagging camera. A small reversal of the ball then does not move the target, which is what keeps the maze from shaking.
- The camera follows when `n_cells > 10` (parameter `FOLLOW_MIN_N = 11`): a (2N+1)-tile map fits rotated on 480 lines only up to N = 10. N = 5 and N = 10 (and smaller legacy sizes) get (0, 0).
- The snap is one clock after `phys_init`, when `ball_physics` has placed the ball at the spawn tile. It does not wait for `phys_done`, because `ball_physics` skips that frame's step after `phys_init`.
- A one-clock `cam_done` pulse marks a new camera value, so Story 7.3 can capture it in the same vertical blanking as the ball overlay.
- Dead zone, shift and follow threshold are module parameters; `labyrinth_pkg.vh` is not changed (it needs all three owners).

</frozen-after-approval>

## Implementation Notes

- Files: new `rtl/camera.v` and `tb/tb_camera.v`; `rtl/My_Top_Module.v` instantiates `camera_i` (outputs unused until 7.3); `tb/run_current_stories.tcl` runs `tb_camera`; `docs/parallel-workstreams.md` gains the camera interface.
- `camera` works in 19 bits internally (a target can be 48 px beyond the ball, and `target - cam` spans twice that) and outputs the ball's 18-bit Q9.8. Two clocks after `phys_done`: clock 1 updates the target, clock 2 steps the camera and pulses `cam_done`.
- `tb_camera` compares the camera with a software model of the same arithmetic on every frame (621 frames). It covers bounces of up to 47 px inside the box, leaving the box at 5 px/frame in both directions and both axes, settling, the offset limit (48 + 40 px per axis, and within 235 px of the screen centre at any angle), snaps on `phys_init`, N = 5 and N = 10, and reset.
- Mutation check: removing the snap, using a logical shift, following from N = 10, or a 20 px dead zone each make `tb_camera` print FAIL lines (360, 572, 122 and 769), so the checks are live. The first draft's own overshoot check was wrong (it compared with the box edge while the ball was still inside the box); it now compares with the target.
- Verification (Vivado 2025.2, run from the scratchpad, 2026-11-01): full `run_current_stories.tcl` PASS (34 PASS lines). Routed top: WNS +0.524 ns, WHS +0.097 ns, all constraints met, 3,336 LUTs, 3,530 registers, 6 DSPs, identical to main, because synthesis removes the unused camera. `camera` placed and routed alone at 100 MHz: WNS +3.640 ns, 168 LUTs, 79 registers, no DSP.
- Not done: board check. Nothing on the screen changes until Story 7.3 connects the camera, so there is nothing to see yet. The independent review layers were not run (no subagents were requested); the review below is the author's own pass.


## Review Triage Log

| Finding | Verdict | Evidence |
|---|---|---|
| The camera's outputs are unused in the top, so the routed build does not time its logic | low | Timed alone instead: WNS +3.640 ns at 100 MHz. Story 7.3 connects it and its routed build covers the real paths |
| The dead-zone box is centred on the target, while the epic text says "around the camera" | low | Deliberate and recorded in the Intent: centring on the lagging camera would let a small reversal move the target and shake the view; both pass the epic's acceptance criteria |
| `>>>` floors, so a positive gap under 8 LSB never closes | low | At most 7/256 px short of the target; invisible. Not worth extra logic |
| The camera also updates in MENU and GENERATE | false | Nothing is drawn there, and `phys_init` snaps it before PLAY |
| `phys_done` in the same clock as `phys_init` could step from a stale target | false | The step is gated with `!phys_init`, and the snap one clock later wins over any step |
| 18-bit output could overflow | false | The ball stays inside the map (under 248 px from the centre), so the camera stays under 296 px, well inside Q9.8's 512 px |
| Independent review (2026-11-01, with Story 7.3): a live `n_cells` change (legacy switches) flipped `follow` and moved the camera without `cam_done` | low | Patched: `follow` is latched on `phys_init`. `tb_camera` now also checks the exact two-clock `cam_done` latency, that the camera changes only with `cam_done` or reset, `phys_done` arriving with or just after `phys_init`, and the on-screen bound in Q9.8. Full triage in the 7.3 spec |
