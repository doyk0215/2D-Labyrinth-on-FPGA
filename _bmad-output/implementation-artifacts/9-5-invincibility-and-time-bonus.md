---
story_id: 9.5
story_key: 9-5-invincibility-and-time-bonus
title: Invincibility and time bonus
status: review
owner: CJX
reviewers: [DY, QZ]
depends_on: [9.2, 8.2]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/65
---

# Story 9.5: Invincibility and time bonus

Based on merged main `a26d9d8`. CJX implements this story at the user's request
while DY handles 9.4. DY remains the listed issue owner and reviews the handoff;
QZ reviews controller/timer interfaces and later roulette integration.

## Behavior and interface

- While INVINCIBLE is active at the pickup edge, a debuff box is consumed and
  starts its normal independent respawn delay. The active protection and its
  seconds/fraction continue without replacement or refresh. Protection covers
  its final clock; a coincident expiration still clears it on that clock.
- A protected debuff publishes the normal one-clock pickup/index event plus
  `debuff_blocked=1`, with `pickup_effect=ITEM_NONE`. This is the 9.7 hook for
  the protection icon, without a debuff roulette. A normal buff can replace
  protection; a time bonus is instant and is the nonreplacement exception.
- TIME_BONUS publishes its chosen ID but never becomes an active timed effect.
  It produces `time_bonus_pulse`, qualified directly by the accepted physics
  completion, PLAY, reset and phys_init. The grant reaches the timer on the
  same edge; the registered pickup notification would be one clock too late
  for the exact deadline case.
- `ITEM_TIME_BONUS_SECONDS=10` on the top feeds `game_timer.BONUS_SECONDS`.
  Values clamp to 0..5999. Mixed-radix BCD addition uses no runtime division,
  modulo or multiplier and caps at 99:59. If a normal second tick coincides,
  decrement first, then add and saturate. The partial-second phase is kept;
  an unarmed timer still waits for visible maze content and first player input.
- A positive grant at 00:01's terminal clock suppresses `time_up`, so the real
  controller remains in PLAY (or accepts a simultaneous goal into WIN) with
  the extended time. A zero/negative configured bonus does not mask a deadline.
  Already-entered WIN/LOSE, reset and phys_init do not accept a bonus.
- Effects and events clear on reset/new maze/non-PLAY as before. SW0 snap,
  SW5 fixed seed, box placement and low-gravity scaling remain unchanged.

9.7 must move activation/grant to its agreed roulette completion boundary and
block pickups while busy. This PR provides the blocked-event and immediate
bonus contract; it does not implement an animation or delay any effect.

## Validation

Vivado 2025.2, 2026-11-02:

- Focused seven-bench suite PASS (`source tb/run_story95.tcl`).
- `tb_time_bonus`: independent integer-seconds scoreboard across 26,000+
  clocks for five parameter variants, all BCD carries, cap, coincident tick,
  empty timer, unchanged first-input arming, minimum clock frequency, reset,
  phys_init and non-PLAY gating; zero/negative/oversized bonus parameters.
- `tb_story95_items`: real item/timer/game controller handshake, invincibility
  consumption and occupied respawn, no timer refresh on blocked debuff or
  bonus, ordinary buff replacement, last protection clock, exact deadline
  pickup with frame_tick and with a simultaneous goal, replay/reset/LOSE.
- `tb_top_story95_buffs`: real generator positions and physics completion,
  full pools, protection and physics bus wiring, instant 00:59 to 01:09 bonus,
  unchanged invincibility OLED row, blocked respawn, replacement and resets.
  Only ball position is placed; RNG candidates/effects/events are not forced.
- Existing timer, item controller, 9.2 top and 8.2 countdown fixtures PASS.
  Their new ports/expectations reflect instant bonus and protected consumption.
- Full 47-run regression PASS, exit 0 with no FAIL markers. Both OLED driver
  modes and the full-frame ball/camera benches passed. The isolated source
  snapshot's RTL matches source commit `5ee692e` (normalizing line endings).
- Full Basys 3 synthesis, implementation and bitstream generation PASS.
  Routed setup +0.178 ns, hold +0.106 ns; DRC 0 errors. Utilization: 4,351 LUTs
  (20.92%), 4,346 registers (10.45%), 3 BRAM tiles, 6 DSPs.
- Local bitstream:
  `C:/EE2026Projects/build-story95-a26d9d8/labyrinth.runs/impl_1/My_Top_Module.bit`
  SHA256: `96FFE2D4AA6C7815BCC58AE924812C110C1DD0CB1E36C2F072842162645AD4D2`.
- PR: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/pull/84.
- Hardware check: pending; no author board PASS claimed.

## Review and non-author board checklist

DY reviews top integration and takeover of the assigned story; QZ reviews
timer/control event semantics. A non-author records commit, PASS/FAIL and a
photo/note before approval/merge, per `docs/parallel-workstreams.md` section 7.3.

1. Pick INVINCIBLE, then roll over a debuff: the box disappears, protection
   continues on its original countdown, and no debuff starts. After the normal
   respawn delay it returns, waiting for departure if still occupied.
2. After protection expires, collect a debuff and verify its selected status.
   Other not-yet-implemented consumers remain placeholders until 9.3/9.4.
3. Collect an ordinary buff during protection and verify replacement. Collect
   TIME_BONUS with a timed effect active: time left gains about 10 seconds,
   including a minute carry; the active effect/countdown is not restarted.
4. Collect a bonus near zero and continue playing. Check a normal timeout
   still enters LOSE without a bonus. Reset/replay clears item state and reloads
   the stage's original time limit.
5. Recheck EASY/HARD/HUGE, mouse/buttons and both SW0 rotation modes. SW5
   remains fixed-seed map selection. Final durations/amounts are tuned in 9.8.
