---
story_id: 9.8
story_key: 9-8-board-playtest-and-tuning
title: Board playtest and tuning
status: in-progress
owner: QZ (lead), DY, CJX
epic: 9
depends_on: [9.3, 9.4, 9.5, 9.7]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/68
---

# Story 9.8: Board playtest and tuning

A team session on the board. It checks every item effect on each stage and
replaces the placeholder numbers with playtested ones. The final values go in
this file, `docs/v2-backlog.md` and the top's parameters.

Rule 7.3: each effect's board check is run by someone other than the story's
author (9.3 QZ, 9.4 DY, 9.5 QZ, 9.7 CJX).

## Build under test

- Main at d385675 (after #87 9.4 and #88 click-gated timer and item counts),
  branch `feature/9-8-board-tuning`, built with `scripts/build_bitstream.tcl`.
- Routed (Vivado 2025.2): timing met, WNS +0.331 ns, WHS +0.086 ns.
  4,969 LUTs, 4,450 registers, 3 BRAM tiles, 6 DSPs. Worst path:
  `ball_x` to `item_i/respawn_left` reset (13 levels).
- The full testbench regression has not been run on this main yet (5.2).

## Tunable values

Every value is a parameter or constant in the RTL. A change needs a rebuild
(about 10 minutes), so try several values in one session and rebuild once.

| Value | Where | Now | Final |
|---|---|---|---|
| Effect duration | `My_Top_Module.v` `ITEM_EFFECT_SECONDS` | 8 s | **10 s** |
| Respawn delay | `My_Top_Module.v` `ITEM_RESPAWN_SECONDS` | 15 s | kept |
| Time bonus | `My_Top_Module.v` `ITEM_TIME_BONUS_SECONDS` | 10 s | kept |
| Fog radius | `My_Top_Module.v` `FOG_RADIUS_PX` | 48 px (3 tiles) | kept |
| Roulette spin | `My_Top_Module.v` `ITEM_ROULETTE_SPIN_MS` | 1500 ms | kept |
| Roulette hold | `My_Top_Module.v` `ITEM_ROULETTE_HOLD_MS` | 1000 ms | kept |
| Blocked-debuff icon | `My_Top_Module.v` `ITEM_BLOCK_ICON_MS` | 1000 ms | kept |
| Time limit EASY | `My_Top_Module.v` `EASY_TIME_SECONDS` | 60 s | kept |
| Time limit HARD | `My_Top_Module.v` `HARD_TIME_SECONDS` | 120 s | kept |
| Time limit N = 15 | `My_Top_Module.v` `HUGE_TIME_SECONDS` | 180 s | kept |
| Loop count K, HARD | `maze_gen.v` `loop_cap` (N = 10) | 3 | kept |
| Loop count K, N = 15 | `maze_gen.v` `loop_cap` (N = 15) | 5 | kept |
| Boxes per stage | `maze_gen.v` `box_target` (#88) | EASY 0, HARD 2+2, N = 15 3+3 | kept |

The last row is not in the 9.8 list; #88 set it. Since EASY has no boxes, the
first acceptance criterion ("every effect on EASY, HARD and N = 15") can only
be run on HARD and N = 15. The team should agree on this and record it here.

## Session checklist

Program the board, then for each of HARD and N = 15:

1. **Timer start.** The countdown does not start on mouse motion, only on the
   first mouse click or BTNL / BTNR press (mouse-only in #88; board buttons
   count again).
2. **Pickup and roulette.** Roll onto a buff box and a debuff box. The OLED
   spins that box's pool for about 1.5 s, holds about 1 s, then shows
   `ITEM:<name> <seconds>`. No box can be picked up while it spins. The box
   disappears and comes back after the respawn delay, and waits if the ball
   is on its cell.
3. **Each effect**, picked up at least once (repeat pickups until each shows):
   - LOW GRAV: the ball falls about half as fast.
   - HIGH GRAV: about twice as fast; it never passes through a wall.
   - ZERO GRAV: a ball at rest stays put; a moving ball keeps going.
   - REVERSE GRAV: the ball falls the other way.
   - INVERT: left and right swap, mouse and buttons, SW0 off and on.
   - FOG: only a circle around the ball shows; the ball always shows.
   - INVINCIBLE: a debuff box gives no effect, shows the invincibility icon
     for about 1 s and is used up; a buff box still replaces the effect.
   - TIME BONUS: the countdown jumps up by the bonus; the active effect keeps
     running. Taken near 00:00, it saves the game.
4. **Countdown against a watch.** The OLED item seconds and the game timer
   each match a phone stopwatch over a full effect and over 60 s.
5. **Clearing.** The effect clears on WIN, LOSE, a replay and a long-press
   reset.
6. **Long session.** Several minutes with boxes active: no tearing or
   stutter on the VGA picture.

Tuning questions to answer while playing: is 8 s long enough to notice an
effect without becoming annoying; does a 15 s respawn leave the map empty
too long; is 48 px of fog fair on N = 15; are the time limits winnable with
the loops and items; is the roulette too slow.

## Results

First session, 2026-11-03, on the d385675 build: every check behaved as
expected. Decision: effect duration 10 s (was 8 s); every other value is
kept. The change is `ITEM_EFFECT_SECONDS = 10` in `My_Top_Module.v`; it was
not rebuilt or played on the board in this story.

Still to record: who ran each effect's check (rule 7.3: DY wrote 9.4, so
INVERT and FOG are checked by QZ or CJX), and the EASY no-boxes decision.
