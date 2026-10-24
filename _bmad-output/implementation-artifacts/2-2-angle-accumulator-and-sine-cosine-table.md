---
story_id: 2.2
story_key: 2-2-angle-accumulator-and-sine-cosine-table
title: Angle accumulator and sine/cosine table
status: review
owner: QZ + DY (trig table)
epic: 2
---

# Story 2.2: Angle accumulator and sine/cosine table

As the player,
I want the maze angle to change smoothly while I hold a button and hold when I release,
So that rotation feels continuous.

## Acceptance Criteria

1. `angle_accumulator` exposes a 12-bit angle, where 4096 represents 360 degrees, and changes it only on `frame_tick`.
2. At the default speed, `rot_cmd=+1` advances the angle by about 90 degrees over 60 frame ticks; the angle wraps at 360 degrees. `rot_cmd=-1` rotates in the opposite direction.
3. When `rot_cmd=0`, the angle remains exactly unchanged across frame ticks. Both/no-button conditions are resolved to `rot_cmd=0` by Story 2.1's `input_mux`.
4. `sincos_rom` provides signed Q1.14 sine and cosine values with one clock of latency. Its bench covers all 4096 angles against a software model, exact key angles, unit-circle error, and latency; maximum error is no more than 2 LSB.

## Implementation Tasks

- [x] Add the quarter-wave `sincos_rom` and generated table source (`rtl/sincos_rom.v`, `scripts/gen_sincos_table.py`).
- [x] Add `tb/tb_sincos_rom.v`; it passes in Vivado 2025.2 with maximum sine and cosine error of 1 LSB.
- [x] Add `rtl/angle_accumulator.v` with frame-tick gating, signed direction, fractional rate division, and 12-bit wraparound.
- [x] Add `tb/tb_angle_accumulator.v` for rate, hold, direction, frame gating, and wraparound.
- [x] Publish the angle and sine/cosine interfaces for the follow-on game-control and render stories.

## Interface Contract

- Inputs: `clk` at 100 MHz, synchronous active-high `rst`, one-cycle `frame_tick`, and signed `rot_cmd[1:0]` (`2'b11` = -1, `2'b00` = 0, `2'b01` = +1).
- Output: unsigned `angle[11:0]`; +1 increases angle, -1 decreases it, modulo 4096.
- The angle accumulator uses the nominal 60-frame/s speed basis: 1024 angle counts per second (90 degrees/s). It distributes the fractional `1024 / 60` step across frame ticks. The actual 800x525 timing is about 59.52 frames/s, yielding about 89.3 degrees/s.
- `sincos_rom` consumes the current angle and presents the corresponding signed Q1.14 values one clock later.

## Verification

Verified with Vivado 2025.2 using `tb/run_story22.tcl`. The angle bench passes rate, hold, direction, frame gating, and both wrap directions; the sine/cosine sweep passes all 4096 angles with maximum error of 1 LSB.
