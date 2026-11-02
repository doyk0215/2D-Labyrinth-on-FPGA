---
story_id: 9.3
story_key: 9-3-gravity-effects
title: Gravity effects
status: in_progress
owner: QZ
epic: 9
depends_on: [9.2]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/63
---

# Story 9.3: Gravity effects

Implement low, high, zero and reverse gravity for item pickups. Story 9.2
already wires the active item code into `ball_physics` and implements low
gravity; this story completes the gravity modes without changing item pickup,
timers, respawn, controls or rendering.

## Baseline

Based on `main` at `a26d9d8` (after Story 9.2 / PR #83). The shared item codes
are defined in `rtl/labyrinth_pkg.vh` and already reach
`ball_physics.effect_code` from `My_Top_Module`.

## Intended behavior

- `ITEM_LOW_GRAV`: half the normal gravity acceleration.
- `ITEM_HIGH_GRAV`: twice the normal gravity acceleration.
- `ITEM_ZERO_GRAV`: no gravity acceleration; current velocity coasts unchanged.
- `ITEM_REVERSE_GRAV`: gravity acceleration points opposite the normal vector.
- The mode applies to both gravity axes and to the fractional carry, so
  fractional acceleration agrees with the selected mode during steady effects
  and when an effect starts or ends.
- The existing per-axis velocity cap remains 5 px/frame. Collision and
  restitution behavior remain unchanged, and no mode may tunnel through a
  wall.
- The constant gravity multiply remains implemented in LUTs, with no increase
  in DSP use; the routed build must meet timing.

## Acceptance criteria

- Given low, high, zero and reverse gravity, after N frames velocity changes
  by half, double, zero and the opposite normal-gravity change, respectively;
  fractional carry is scaled consistently with each mode.
- Given any gravity effect, the tunnelling bench confirms the ball never
  crosses a wall and the 5 px/frame per-axis speed cap holds.
- Given the routed build, the gravity multiply remains in LUTs with no extra
  DSPs and timing is met.

## Implementation notes

- Extend the existing effect snapshot in `rtl/ball_physics.v` to capture the
  selected gravity mode with the frame's settled sine/cosine values. Keep that
  mode stable through the multiply and accumulator pipeline so a mid-frame
  effect transition cannot mix modes.
- Scale the full signed gravity product before splitting integer acceleration
  and fractional carry. Use shifts, zeroing and sign inversion for the four
  modes; preserve the existing constant-multiply `use_dsp = "no"` constraint.
- Preserve the existing gravity coefficient, frame cadence, velocity
  saturation, collision reads, wall response, and `phys_done` timing.
- Story 9.2 already includes the low-gravity path and a partial
  `tb_item_gravity` bench. Extend that bench with an independent fixed-point
  model for all four modes, all gravity octants, mode transitions, wall
  collisions and the unchanged cap. Keep the normal-gravity physics bench
  passing.
- Do not implement invert controls, fog, invincibility, time bonus, roulette,
  or changes to the item effect pools; those belong to Stories 9.4, 9.5 and 9.7.

## Implementation status

`rtl/ball_physics.v` now snapshots the full effect code with the frame's
settled trig values and scales the signed gravity product before the
integer/fraction split: low shifts right, high shifts left, zero clears the
product, reverse negates it, and unrelated item effects retain normal gravity.
The product remains marked `use_dsp = "no"`. Functional, routed-build and board
verification are still pending.

## Code map

- `rtl/ball_physics.v` — capture and apply all gravity effect codes while
  keeping the fractional accumulator and collision pipeline correct.
- `tb/tb_item_gravity.v` — cover low/high/zero/reverse fixed-point behavior,
  including fractional carry and entry/exit transitions, and exercise the
  unchanged no-tunnelling and speed-cap guarantees.
- `tb/tb_ball_physics.v` — retain the existing normal-gravity collision and
  tunnelling regression.
- `tb/run_story93.tcl` — add a focused Vivado runner for the gravity benches.
- `tb/run_current_stories.tcl` and the routed build — verify regression and
  resource/timing impact against the merged 9.2 baseline.

## Verification plan

1. Run the focused Story 9.3 Vivado benches and the existing ball-physics
   bench. Check signed acceleration, carried fractions, effect transitions,
   all octants, all restitution settings, wall containment and the 5 px/frame
   cap.
2. Run the current-story regression.
3. Run synthesis and implementation from the Story 9.3 branch. Record timing,
   LUT and DSP counts; confirm the gravity multiply uses LUTs, DSP count does
   not increase from the 9.2 baseline, and timing is met.
4. Record the tested commit and routed results in this artifact. A teammate
   other than the story author performs the board check and records PASS/FAIL
   on the PR, per `docs/parallel-workstreams.md`.

## Board check

Use the four gravity pickups on the Basys 3 and confirm low/high acceleration,
zero-gravity coasting, and reverse acceleration are distinguishable. Check
that the ball remains inside maze walls and that no effect exceeds the normal
5 px/frame per-axis cap. Record the tested commit and result on the PR.

## Results

RTL implementation is present in the working tree. Simulation,
routed-build/resource and board results remain to be recorded.
