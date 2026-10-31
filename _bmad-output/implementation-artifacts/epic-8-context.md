# Epic 8 Context: Win polish and time limit

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A better win screen and a countdown time limit in every game that can end it. v1 shows a plain YOU WIN panel and an elapsed-time counter on the OLED; v2 makes the finish rewarding (blinking goal, time left on the panel) and adds pressure (countdown, LOSE state, TIME UP screens).

## Stories

- Story 8.1: Win screen polish
- Story 8.2: Countdown timer and LOSE state
- Story 8.3: TIME UP screens

## Requirements & Constraints

- The time limit applies to every game (EASY 60 s, HARD 120 s, N = 15 180 s); there is no separate time-limit mode.
- The panel and the OLED must agree on the time shown, and the blink must not flicker.
- Everything drawn on the monitor changes only in vertical blanking, so a frame never mixes two states.
- Timing stays met and resources stay within the project caps; the physics step still finishes in vertical blanking.

## Technical Decisions

- `game_timer` is the single source of the time (BCD minutes and seconds). It counts only in PLAY, freezes in WIN and clears on `phys_init`; Story 8.2 turns it into a countdown without changing its ports.
- `render` captures `game_state`, and any value it draws, together with the sin/cos snapshot at `frame_tick_d[1]` in vertical blanking. New per-frame values follow this rule.
- `win_overlay` draws the fixed screen-space panel with the shared 5x7 `font_rom` (one clock of latency); its outputs line up with `render`'s one-clock pixel latency.
- `game_state` is 2 bits today; Story 6.1 widens it to 3 bits with LOSE reserved, so new code should not compare it to bare numbers where avoidable.
- Single writer per file (AD-5): `render` and `win_overlay` belong to the graphics owner, `game_timer` and `game_ctrl` to the input and game-control owner.

## UX & Interaction Patterns

- WIN: green outline and a dark-blue panel with white text over the maze; the goal tile blinks at a few Hz.
- LOSE (8.2, 8.3): a TIME UP panel on the monitor, TIME UP on the OLED, then back to the menu after a short hold.

## Cross-Story Dependencies

- 8.1 needs nothing; it shows whatever `game_timer` holds, which becomes the time left when 8.2 lands.
- 8.2 needs 6.1 (shared state encoding); 8.3 needs 8.2.
- 9.5 (time bonus) extends the countdown from 8.2.
