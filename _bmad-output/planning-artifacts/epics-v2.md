---
status: draft
inputDocuments:
  - docs/v2-backlog.md
  - _bmad-output/planning-artifacts/epics.md
---

# 2D-Labyrinth-on-FPGA - v2.0 Epic Breakdown

This document turns `docs/v2-backlog.md` into stories. v1.0 stories stay in `epics.md`; v2.0 continues the numbering from Epic 6. Placeholder numbers (times, counts, delays) are parameters to settle in playtesting.

## Sizing

| Size | Meaning |
| --- | --- |
| S | About half a day to one day: one or two modules, one bench, one board check. |
| M | About one to two days: three or more modules, or a new bench with real coverage. |

No story is larger than M. Anything bigger was split. Streams follow `docs/parallel-workstreams.md`: A = physics, maze generation, OLED driver; B = input and game control; C = graphics and top level. Owners are not assigned yet.

## Story list

| Story | Title | Size | Stream | Needs |
| --- | --- | --- | --- | --- |
| 6.1 | Shared game-state encoding | S | B | none |
| 6.2 | Long-press BTNC full reset | S | B | none |
| 7.1 | Map size follows the stage | M | A | none |
| 7.2 | Camera that follows the ball | S | C | 7.1 |
| 7.3 | Draw the N = 15 map | M | C | 7.1, 7.2 |
| 7.4 | Add the N = 15 stage | S | B | 7.1, 7.3 |
| 7.5 | Loops on HARD and larger | M | A | 7.1 |
| 8.1 | Win screen polish | S | C | none |
| 8.2 | Countdown timer and LOSE state | M | B | 6.1 |
| 8.3 | TIME UP screens | S | B + C | 8.2 |
| 9.1 | Place and draw item boxes | M | A + C | 7.5 |
| 9.2 | Pickup, effect timer and respawn | M | B | 9.1 |
| 9.3 | Gravity effects | M | A | 9.2 |
| 9.4 | Invert controls and fog of war | M | B + C | 9.2 |
| 9.5 | Invincibility and time bonus | S | B | 9.2, 8.2 |
| 9.6 | Item icons | S | C | none |
| 9.7 | OLED item roulette | M | A + B | 9.2, 9.6 |
| 9.8 | Board playtest and tuning | S | A | 9.3, 9.4, 9.5, 9.7 |

Total: 18 stories (10 S, 8 M).

Suggested order: 6.1 and 6.2 first (6.1 touches many files and 8.2 adds the LOSE state); then 7.1, then 7.2 to 7.4 with 7.5 alongside; 8.1 any time; 8.2 and 8.3 after 6.1; the item-box epic last.

## Epic 6: v2.0 groundwork

The design gets named state and config encodings, and a way out of a lock-up.

### Story 6.1: Shared game-state encoding

As a developer,
I want one definition of the game states,
So that adding a state does not mean editing literals in five modules.

**Size:** S. **Needs:** none.

**Acceptance Criteria:**

**Given** `game_state` is compared by literal in `My_Top_Module`, `render`, `game_timer`, `oled_status_text` and `game_ctrl`
**When** the states are moved to shared `localparam`s (or macros in `labyrinth_pkg.vh`) and `game_state` is widened to 3 bits with LOSE reserved but unused
**Then** the full regression passes unchanged and no file compares `game_state` to a bare number

**Given** the routed build
**When** `game_state` is 3 bits
**Then** timing is still met and `game_cfg` stays at 8 bits (the time limit is not a setting)

### Story 6.2: Long-press BTNC full reset

As an examiner,
I want to recover from a lock-up without reprogramming the board,
So that a demo is never stuck.

**Size:** S. **Needs:** none.

**Acceptance Criteria:**

**Given** any state
**When** BTNC is held for the long-press time (a parameter, about 2 s)
**Then** the game, menu, mouse and OLED reset as at power-on and no stage starts

**Given** a short BTNC press
**When** it is released
**Then** it still confirms in MENU and returns to MENU elsewhere, and a long press does not also fire the short-press action on press or on release

**Given** the testbench
**When** a long press is applied from MENU, GENERATE, PLAY and WIN
**Then** each ends in a freshly initialised MENU and the OLED re-runs its start-up

## Epic 7: Bigger and harder mazes

A third stage, N = 15, and mazes with more than one route.

### Story 7.1: Map size follows the stage

As a developer,
I want the map dimensions to follow the stage instead of being fixed to 21 x 21,
So that a larger stage needs no more structural change.

**Size:** M. **Needs:** none.

**Acceptance Criteria:**

**Given** `MAP_DIM`, `MAP_ADDR_W`, the centring offset and the generator stack size
**When** they depend on the stage's N (2N + 1 tiles per side, a 10-bit address and a 225-entry stack for N = 15)
**Then** `maze_ram`, `maze_gen`, `render` and `ball_physics` build for N up to 15 and the existing N = 5 and N = 10 regression passes unchanged

**Given** the generator bench
**When** N = 15 mazes are generated for many seeds
**Then** every maze is perfect and solvable, the stack never overflows, and results are deterministic per seed

**Given** `ball_physics` at N = 15 in simulation
**When** the existing bounce, tunnelling and goal tests run on a 31 x 31 map
**Then** they pass

### Story 7.2: Camera that follows the ball

As the player,
I want the view to follow the ball on the N = 15 stage without shaking,
So that a maze larger than the screen is playable at any angle.

**Size:** S. **Needs:** 7.1.

**Decision.** The N = 15 map is shown through a camera that follows the ball. The other two options fail at 45 degrees: a 31 x 31 map needs a tile of about 10 px or less to fit rotated, which is no bigger than the ball, and a 15 px tile still clips (about 658 px across the diagonal). The camera keeps the 16 px tile, so physics, the ball and the goal test do not change. N = 5 and N = 10 keep the fixed view (camera pinned at the map centre), so they look as they do today.

**Design.**
- A new `camera` module owns the camera position `cam_x`, `cam_y` (Q9.8 maze pixels from the map centre, the same format as the ball position; AD-5 single writer).
- It updates once per frame on `phys_done`, so it uses this frame's ball position. Capturing it with render's sin/cos snapshot would be one frame late, because that snapshot is taken before physics runs.
- **Dead zone:** while the ball is within a box around the camera (parameter, about ±48 px in maze coordinates), the target does not move. Outside it, the target moves just far enough to bring the ball back to the box edge. Bounces (about 21 px high at EASY restitution and 47 px at HARD) stay inside the box, so the maze does not shake.
- **Smoothing:** `cam += (target - cam) >>> CAM_SHIFT` (parameter, about 3), shift and add only, no multiplier.
- **Snap:** on `phys_init` (new maze, replay, reset) the camera jumps straight to the ball, so it does not sweep across the maze.
- **Fixed stages:** for N = 5 and N = 10 the camera output is the map centre.

**Acceptance Criteria:**

**Given** the camera bench with a scripted ball path
**When** the ball moves inside the dead zone, including repeated bounces of up to 47 px
**Then** the camera does not move

**Given** the ball leaves the dead zone at the 5 px/frame cap
**When** frames pass
**Then** the camera follows without overshoot, the ball's offset from the camera stays within the dead zone plus the smoothing lag (about 48 + 40 px), and the ball stays on screen at every angle

**Given** `phys_init`
**When** it pulses
**Then** the camera equals the ball position on that frame

**Given** an N = 5 or N = 10 game
**When** it runs
**Then** the camera output is the map centre on every frame

### Story 7.3: Draw the N = 15 map

As the player,
I want the larger maze drawn correctly at any angle,
So that I can play it.

**Size:** M. **Needs:** 7.1, 7.2.

**Design.**
- `render` replaces the constant `MAP_CENTRE_Q` with the camera position (`cam << 6` plus the map centre, Q13.14). The per-frame part of the scanline start (camera minus 320 x cos or sin) is registered in vertical blanking, so the per-scanline adder is no deeper than today.
- `ball_overlay` takes `ball - cam` instead of `ball`; its rotation is unchanged, so the DSP count does not change.
- `render` draws only the stage's own tiles, not the whole 31 x 31 map, so N = 5 and N = 10 do not show a large wall border.
- The camera, the ball overlay and the render snapshot all change in the same vertical blanking interval, so a frame never mixes two camera positions.

**Acceptance Criteria:**

**Given** an N = 15 maze and a set of camera positions, including near each map edge
**When** it is rendered at 0, 45, 90 and 135 degrees
**Then** the raster bench matches the software model, and pixels outside the map show the background

**Given** the ball and the camera in the top-level bench
**When** the ball moves and bounces
**Then** the drawn ball stays aligned with the physics position and the picture does not tear

**Given** the existing N = 5 and N = 10 stages
**When** the render bench runs
**Then** it passes unchanged

**Given** the routed build
**When** it completes
**Then** timing is met and resources stay within the AD-8 caps

### Story 7.4: Add the N = 15 stage

As the player,
I want a third stage in the menu,
So that I can choose the biggest maze.

**Size:** S. **Needs:** 7.1, 7.3.

**Acceptance Criteria:**

**Given** the stage page on the OLED
**When** a third entry (for example STAGE 3 HUGE) is added and selected with btnU and btnD
**Then** it shows correctly, starts an N = 15 game and is captured as the active stage at game start

**Given** the status text in PLAY and WIN
**When** stage 3 is active
**Then** the OLED shows its name and the timer as for the other stages

**Given** the board
**When** an N = 15 game is played
**Then** the ball starts at the bottom-right start tile, the goal at the top-left is reachable and the win flow works

### Story 7.5: Loops on HARD and larger

As the player,
I want harder stages to offer more than one route,
So that the maze is not a single path to follow.

**Size:** M. **Needs:** 7.1.

**Acceptance Criteria:**

**Given** a HARD or N = 15 maze
**When** generation finishes
**Then** K interior walls (a fixed per-stage parameter: HARD 5, N = 15 7) between two floor cells are removed, outer walls are untouched, and `maze_gen` is still the only writer of `maze_ram`

**Given** the generator bench
**When** many seeds run
**Then** EASY mazes are still perfect, loop stages are connected with exactly (cells - 1 + K) openings, start and goal are reachable, and output is deterministic per seed

**Given** the architecture spine
**When** it is updated
**Then** its "perfect maze" wording says "connected, with K extra openings on loop stages"

## Epic 8: Win polish and time limit

A better win screen and a countdown, in every game, that can end the game.

### Story 8.1: Win screen polish

As the player,
I want the win screen to show my time left and highlight the goal,
So that finishing feels rewarded.

**Size:** S. **Needs:** none.

**Acceptance Criteria:**

**Given** WIN
**When** the picture is drawn
**Then** the goal tile blinks at a few Hz and the panel shows the time left as `mm:ss` from `game_timer`

**Given** the render bench
**When** `tb_win_render` runs at known frames
**Then** the time glyphs and the blink phase match the model

**Given** the board
**When** a game is won
**Then** the time on the panel matches the OLED and the blink does not flicker

### Story 8.2: Countdown timer and LOSE state

As the player,
I want a time limit that can end the game,
So that there is pressure to finish.

**Size:** M. **Needs:** 6.1.

**Acceptance Criteria:**

**Given** any game
**When** it starts
**Then** `game_timer` counts down from the stage's limit (parameters: EASY 60 s, HARD 120 s, N = 15 180 s) in PLAY, freezes in WIN, and the OLED shows the time left

**Given** the countdown reaches 00:00
**When** the next frame is processed
**Then** `game_ctrl` enters LOSE, physics and rotation freeze, and after a hold (about 2 s) the game returns to MENU

**Given** the Story 4.4 benches
**When** the timer changes from count-up to count-down
**Then** they are updated to the new behaviour (clear on `phys_init`, PLAY-only counting, WIN freeze, reset), and all Story 3.3 behaviour is unchanged

### Story 8.3: TIME UP screens

As the player,
I want to see clearly when I run out of time,
So that I understand the result.

**Size:** S. **Needs:** 8.2.

**Acceptance Criteria:**

**Given** LOSE
**When** it is active
**Then** the monitor shows a "TIME UP" panel and the OLED shows "TIME UP", and reset from LOSE returns to MENU

**Given** the board
**When** EASY and HARD are played to a timeout
**Then** the countdown matches a watch and the TIME UP screen appears and returns to the menu

## Epic 9: Item boxes

Buff and debuff pickups that give a random timed effect.

### Story 9.1: Place and draw item boxes

As the player,
I want to see boxes in the maze,
So that I can choose to roll onto them.

**Size:** M. **Needs:** 7.5.

**Acceptance Criteria:**

**Given** a generated maze
**When** `maze_gen` finishes
**Then** 2 buff boxes and 2 debuff boxes are placed on floor cells that are not the start or goal and not shared, storage is added, and the maze is still solvable

**Given** the render bench
**When** boxes are drawn
**Then** the buff box (green and blue) and debuff box (red) each carry a white "?" glyph that cannot be mistaken for the red start tile or the green goal tile

**Given** the generator bench
**When** many seeds run
**Then** box positions are valid, unique and deterministic per seed

### Story 9.2: Pickup, effect timer and respawn

As the player,
I want a box to give me an effect and later come back,
So that the maze stays interesting.

**Size:** M. **Needs:** 9.1.

**Acceptance Criteria:**

**Given** the ball's centre enters a box tile
**When** the next frame is processed
**Then** `item_ctrl` rolls an effect from that box's pool, starts a timer of about 8 s, replaces any active effect, and the box disappears

**Given** a picked-up box
**When** the respawn delay (a parameter, about 15 s) ends
**Then** it reappears in its cell, waits while the ball is on it, and rolls a fresh effect when next picked up

**Given** a replay, reset, WIN or LOSE
**When** it happens
**Then** the active effect and respawn timers clear

**Given** the OLED
**When** an effect is active
**Then** a line shows its name and the seconds left (for example `ITEM: LOW GRAV 06`)

*(This story includes one stub effect, low gravity, so the engine can be tested end to end; the other effects are in 9.3 to 9.5. Here the effect starts at pickup; 9.7 delays the start until the OLED roulette stops.)*

### Story 9.3: Gravity effects

As the player,
I want gravity effects that change how the ball moves,
So that boxes feel different from one another.

**Size:** M. **Needs:** 9.2.

**Acceptance Criteria:**

**Given** low, high, zero and reverse gravity
**When** each is active
**Then** after N frames the velocity is half, double, unchanged, and in the opposite direction compared with normal gravity, with the carried fraction bits scaled the same way

**Given** any gravity effect
**When** the tunnelling bench runs
**Then** the ball never crosses a wall and the 5 px/frame speed cap still holds

**Given** the routed build
**When** it completes
**Then** the gravity multiply is still in LUTs (no extra DSPs) and timing is met

### Story 9.4: Invert controls and fog of war

As the player,
I want a debuff that flips my controls and one that hides the maze,
So that debuff boxes are a real risk.

**Size:** M. **Needs:** 9.2.

**Acceptance Criteria:**

**Given** invert controls
**When** it is active
**Then** left rotation becomes right and right becomes left for the mouse and buttons, in both smooth and snap modes, and it stops when the effect ends

**Given** fog of war
**When** it is active
**Then** pixels farther than the radius from the ball are blank and pixels inside are drawn normally, checked at the fog edge in the render bench

**Given** the routed build
**When** it completes
**Then** timing is met and resources stay within the AD-8 caps

### Story 9.5: Invincibility and time bonus

As the player,
I want buffs that protect me and give me time,
So that buff boxes are worth hitting.

**Size:** S. **Needs:** 9.2, 8.2.

**Acceptance Criteria:**

**Given** invincibility is active
**When** the ball rolls onto a debuff box
**Then** nothing starts, the invincibility continues and the debuff box is consumed (it respawns after the normal delay); a buff box still works and replaces it; once it ends, debuff boxes work again

**Given** a time bonus
**When** it is picked up
**Then** the amount (a parameter, about 10 s) is added to the countdown, capped at 99:59, without replacing the active effect

**Given** the benches
**When** they run
**Then** both effects are covered, including a bonus near 00:00 that extends the game instead of ending it

### Story 9.6: Item icons

As the player,
I want each item to have its own picture,
So that I can tell at a glance what I got.

**Size:** S. **Needs:** none.

**Design.**
- 8 icons, one per effect: low gravity, invincibility and time bonus (buff); reverse, high and zero gravity, invert controls and fog of war (debuff).
- Each icon is 16 x 16 pixels with 2-bit colour indices: 0 = black, 1 = frame, 2 and 3 = the icon's own two colours. Buff icons have a green frame and debuff icons a red one, matching the boxes.
- A per-icon palette of four RGB565 colours sits beside the index ROM (8 x 256 x 2 bits, about 4 kbit, in LUT ROM or part of one block RAM).
- The art is kept as text grids in `scripts/make_item_icons.ps1`, which writes `item_icons.mem` (indices), `item_icons_palette.mem` (RGB565) and a PNG preview sheet.
- The art was approved on 2026-10-30; the approved sheet is `docs/v2-item-icons.png`. Changes to the grids or colours need the team's approval again.

**Acceptance Criteria:**

**Given** the 8 icon grids
**When** the script runs
**Then** it writes both `.mem` files and a preview sheet that matches `docs/v2-item-icons.png`

**Given** the icon ROM bench
**When** every pixel of every icon is read
**Then** the colour matches the preview sheet

### Story 9.7: OLED item roulette

As the player,
I want the OLED to spin through the possible items and stop on the one I got,
So that picking up a box feels like a lucky draw.

**Size:** M. **Needs:** 9.2, 9.6.

**Design.**
- `item_ctrl` still decides the effect at pickup (LFSR); the roulette only animates towards that result.
- While the roulette runs, the OLED shows only the roulette: no text. The icon is drawn at 3x scale (48 x 48) in the middle of the 96 x 64 screen on black.
- The icons of that box's pool (3 for a buff box, 5 for a debuff box) cycle in one slot, starting fast and slowing down, for about 1.5 s (a parameter), then stop on the chosen icon. The chosen icon stays for about 1 s (a parameter), then the OLED returns to the status page with the effect line.
- The game keeps running during the roulette. The effect, or the time bonus, starts when the roulette stops.
- Boxes are not picked up while a roulette is running; the ball rolls over them and they stay.
- A debuff box blocked by invincibility shows no roulette; the OLED shows the invincibility icon for about 1 s instead.
- The OLED pixel stream gets a second source: `oled_text_pixel` for the status page, and a new icon source for the roulette, chosen per frame so a frame never mixes the two.

**Acceptance Criteria:**

**Given** a pickup in the bench
**When** the roulette runs
**Then** only icons from that box's pool appear, the steps slow down, and the last icon is the effect `item_ctrl` chose

**Given** the roulette stops
**When** the hold time ends
**Then** the effect starts on that frame and the OLED returns to the status page

**Given** the OLED frame bench
**When** a roulette frame is captured
**Then** it contains no text pixels and the icon matches the ROM at 3x scale

**Given** a replay, reset, WIN or LOSE during a roulette
**When** it happens
**Then** the roulette stops, no effect starts and the OLED shows the page for the new state

### Story 9.8: Board playtest and tuning

As the examiner,
I want the item boxes checked on the board,
So that the placeholder numbers are replaced by playtested ones.

**Size:** S. **Needs:** 9.3, 9.4, 9.5, 9.7.

**Acceptance Criteria:**

**Given** the board
**When** every effect is picked up on EASY, HARD and N = 15
**Then** each behaves as specified and the OLED countdown matches a watch

**Given** the placeholders (effect duration, respawn delay, time bonus amount, fog radius, loop count K, time limits, roulette spin and hold times)
**When** they are playtested
**Then** final values are recorded in the spec and the v2.0 backlog

**Given** a several-minute session with boxes active
**When** the ball is played
**Then** no picture tearing or stutter is seen
