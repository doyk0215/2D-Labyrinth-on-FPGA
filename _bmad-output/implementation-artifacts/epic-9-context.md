# Epic 9 Context: Item boxes

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Buff and debuff boxes in the maze give the ball a random timed effect, with the OLED showing a roulette that stops on the item obtained. This makes each run different and gives the player risky choices. Everything is a parameter to playtest, so the last story tunes the numbers on the board.

## Stories

- Story 9.1: Place and draw item boxes
- Story 9.2: Pickup, effect timer and respawn
- Story 9.3: Gravity effects
- Story 9.4: Invert controls and fog of war
- Story 9.5: Invincibility and time bonus
- Story 9.6: Item icons
- Story 9.7: OLED item roulette
- Story 9.8: Board playtest and tuning

## Requirements & Constraints

- Two buff boxes and two debuff boxes per maze, on floor cells that are not the start or goal; boxes respawn after a delay. Only one effect is active at a time; a new pickup replaces the old one.
- Eight effects: three buffs (low gravity, invincibility, time bonus) and five debuffs (reverse, high and zero gravity, invert controls, fog of war). Invincibility makes debuff boxes do nothing but consume them.
- While a roulette runs the OLED shows only the roulette (no text) and boxes cannot be picked up.
- Physics still finishes in vertical blanking; the gravity multiply stays in LUTs; resources stay within the project caps.

## Technical Decisions

- `item_ctrl` (new, one owner) decides the effect at pickup and owns the effect and respawn timers; other modules only read its outputs.
- Icons are 16 x 16 with 2-bit colour indices and a four-colour RGB565 palette per icon, in a small LUT ROM generated from `scripts/make_item_icons.ps1`. Icon order: 0 low gravity, 1 invincibility, 2 time bonus, 3 reverse gravity, 4 high gravity, 5 zero gravity, 6 invert controls, 7 fog of war. Index 0 is black, 1 is the frame (green for buffs, red for debuffs).
- The OLED pixel stream gets a second source for the roulette, chosen per frame.

## Cross-Story Dependencies

- 9.1 needs 7.5; 9.2 needs 9.1; 9.3, 9.4 and 9.7 need 9.2; 9.5 needs 9.2 and 8.2.
- 9.6 needs nothing and feeds 9.7.
