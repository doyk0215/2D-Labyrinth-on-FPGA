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
- Invert controls swaps left and right rotation, for the mouse and the buttons, in smooth and snap modes. Fog of war draws only what is within a radius of the ball.
- While a roulette runs the OLED shows only the roulette (no text) and boxes cannot be picked up.
- Physics still finishes in vertical blanking; the gravity multiply stays in LUTs; resources stay within the project caps (no more than 8 DSPs, 50% LUTs, 30% flip-flops, 6 block RAM tiles); routed timing is met at 100 MHz.

## Technical Decisions

- `item_ctrl` (one owner) decides the effect at pickup and owns the effect and respawn timers; other modules only read its outputs (the active effect code and its seconds left).
- Effect codes are shared header constants, 0 to 7 in icon order (0 low gravity, 1 invincibility, 2 time bonus, 3 reverse gravity, 4 high gravity, 5 zero gravity, 6 invert controls, 7 fog of war), with a separate "none" code.
- Invert controls: flip the sign of the rotation command in the top level, on both the smooth and the snap path.
- Fog of war: `render` blanks pixels whose screen distance from the ball exceeds a radius, reusing the squared-distance structure `ball_overlay` already uses for the ball.
- Icons are 16 x 16 with 2-bit colour indices and a four-colour RGB565 palette per icon, in a small LUT ROM generated from `scripts/make_item_icons.ps1`. Index 0 is black, 1 is the frame (green for buffs, red for debuffs).
- The OLED pixel stream gets a second source for the roulette, chosen per frame.

## Cross-Story Dependencies

- 9.1 needs 7.5; 9.2 needs 9.1; 9.3, 9.4 and 9.7 need 9.2; 9.5 needs 9.2 and 8.2.
- 9.6 needs nothing and feeds 9.7.
- The fog radius depends on the final map size; 9.8 tunes it with the other effect parameters.
