---
story_id: 9.7
story_key: 9-7-oled-item-roulette
title: OLED item roulette
status: review
owner: CJX
reviewers: [QZ, DY]
depends_on: [9.2, 9.6, 9.5]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/67
---

# Story 9.7: OLED item roulette

The user initially requested CJX's hooks, then explicitly requested the full
story including QZ's OLED portion, with QZ reviewing. This branch builds on
Story 9.5 PR #84 (`db4eaf8`) so it can handle its instant bonus and protected
debuff semantics; its PR targets that branch until 9.5 merges.

## Confirmed timing decision

On 2026-11-02 CJX chose to start the effect/time bonus when the spin stops and
the selected icon first appears. The selected icon remains about 1 s while
the effect runs, then status returns. This explicitly overrides the original
acceptance text that started effects after the hold. Revisit during 9.8.

## Implementation

- `item_ctrl` still rolls the full pool at pickup, consumes the chosen slot,
  and starts its independent respawn. With `DEFER_EFFECT=1`, it holds the chosen
  code pending and leaves the previous effect/timer running. Busy or pending
  blocks further pickups; boxes rolled over remain present. A valid commit
  applies the held selection exactly once. TIME_BONUS preserves the current
  effect and emits its same-edge grant to `game_timer` at activation.
- `item_roulette` runs on the system clock. It starts timing after the first
  icon frame is acknowledged, cycles only the buff (0..2) or debuff (3..7)
  pool, and increases its step interval over four quarters of the spin. The
  final result is the saved selection, regardless of later RNG progression.
- The result activates only when the OLED confirms a frame showing that
  selected stopped icon. A one-second hold follows, then the controller waits
  for an acknowledged status frame before accepting another pickup. Spin,
  result hold and protected notification default to 1500/1000/1000 ms, exposed
  as top parameters for 9.8 tuning. Durations clamp to at least one clock.
- A protected debuff is consumed normally and shows only the INVINCIBLE icon
  for the notification duration. It starts no spin/pending effect/commit, and
  leaves protection's countdown running. Pickups also wait through this notice.
- Reset, new maze, MENU/GENERATE/WIN/LOSE cancel animation and pending work.
  A transition before result display cannot activate anything later. If the
  effect already started at spin stop, terminal-state clearing applies normally;
  an already-applied instant bonus is not retroactively removed.
- `oled_roulette_pixel` draws the existing 16x16 ROM at exactly 3x scale in the
  centre of the 96x64 display (x=24..71, y=8..55), black everywhere else. It has
  the same one-clock pixel response as the text source. ROM assets are unchanged.
- The held-data text mailbox now transfers source/icon metadata atomically
  with the text page. The OLED domain applies both only at its frame boundary.
  A frame toggle plus held visual data reports the applied frame back to the
  system domain, qualified by the SPI driver's actual pixel request. Power-up
  frame-counter boundaries cannot start animation/activation before the driver
  is ready. No unsynchronised multi-bit visual state drives activation.
  Text is composed while icons are displayed; a complete live page is ready
  when status returns. The SPI/power driver is unchanged.
- Shipping `My_Top_Module.ITEM_ROULETTE_ENABLE` defaults true. Direct standalone
  `item_ctrl` keeps its immediate default for existing module consumers. Old
  9.2/9.5 top fixtures explicitly select immediate mode to retain their original
  scope; the new top integration uses shipping roulette mode. No switch is used.

## Validation

Vivado 2025.2, 2026-11-02:

- Focused nine-bench suite PASS (`source tb/run_story97.tcl`).
- `tb_item_roulette`: all eight selections and correct pools, monotonic step
  intervals, multiple icon cycles, selected hold, activation at stopped-result
  frame, busy consumption gating, saved selection despite RNG changes, blocked
  icon without activation, every phase/non-PLAY cancellation, reset/new maze.
  A delayed TIME_BONUS acknowledged on the exact final countdown clock suppresses
  the deadline and extends 00:01 to 00:10 on that edge.
- `tb_oled_roulette_pixel`: all 49,152 pixels across all eight 96x64 frames
  match independent ROM data/palette lookup, including every 3x replicated pixel
  and black margin. Invalid addresses are black.
- `tb_top_story97_roulette`: real generated boxes/physics completion, a complete
  6,144-pixel icon-only top frame with no text/mixed icons, frame-boundary metadata,
  ongoing game countdown/physics, unchanged rolled-over busy boxes, actual
  selected-frame activation, blocked notice, exactly one delayed time bonus,
  live status return and LOSE/full-reset cancellation. An unready power-up frame
  is explicitly rejected. Only ball placement and OLED frame/pixel requests are
  supplied by the fixture; RNG/effects are not forced. The unchanged SPI driver
  retains its separate nominal-clock initialization/frame regressions.
- Prior item/timer/top/OLED fixtures PASS in the focused suite.
- Full 50-run regression and routed Basys 3 build: running; results pending.
- Hardware check: pending; no author board PASS claimed.

## Non-author review and board checklist

QZ reviews the OLED controller/pixel source, clock-domain mailbox and chosen
activation timing. DY reviews top integration. A non-author records commit,
PASS/FAIL and a photo/note before approval/merge, per the v2 workflow.

1. Collect each box type on EASY/HARD/HUGE. Only its pool's icons spin, visibly
   slowing for about 1.5 s; the selected icon then stays about 1 s with no text.
2. Confirm the chosen effect begins when the spin stops, while its icon is
   held. A time bonus adds the configured amount once at that point, preserving
   any current effect. The result hold consumes about 1 s of a timed effect.
3. Keep moving during spin/hold: the maze, ball and game timer continue. Roll
   across another box: it remains available until this notice/roulette finishes.
4. While invincible, hit a debuff. It disappears and shows only the protection
   icon for about 1 s; protection continues on its old countdown. The consumed
   box still follows its ordinary respawn and occupied-cell rules.
5. Reset/replay, win or time out during animation. Pending work cancels and the
   correct new status page appears; no later effect/bonus starts. Check both
   SW0 rotation modes and SW5 fixed-seed behavior.
6. Run for several minutes; no OLED text/icon tearing or VGA stutter. Tune
   spin/hold/notification durations and activation timing in 9.8.
