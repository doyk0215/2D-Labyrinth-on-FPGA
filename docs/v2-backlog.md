# v2.0 Backlog — 2D Labyrinth on FPGA

Features deferred past the graded v1.0 build. Each entry says why it came up, what it should do, and how to check it. Story details for v1.0 stay in `_bmad-output/planning-artifacts/epics.md`. The v2.0 stories, with sizes, are in `_bmad-output/planning-artifacts/epics-v2.md`.

## 1. Long-press BTNC full reset

**Why.** Since Story 4.2 (PR #40), BTNC is a short-press button: in MENU it confirms the stage, and in GENERATE, PLAY or WIN it returns to MENU. The only full reset is the power-on reset (`por_reset`). If the design ever locks up in MENU or in the OLED path, the only way out is to reprogram the board.

**What.**
- Holding BTNC for a long press (for example 2 s, a parameter such as `LONG_PRESS_CYCLES`) asserts the same full reset as power-on: game, menu, mouse and OLED.
- A short press keeps its Story 4.2 meaning: confirm in MENU, return to MENU elsewhere.
- The long press must not also fire the short-press action, either when it is first pressed or when it is released.

**Where.** `rtl/My_Top_Module.v`: extend the BTNC debouncer (`button_press_debounce`) with a held-time counter, or add a small long-press detector, and OR its pulse into the reset that `por_reset` drives.

**Check.**
- Testbench: a short press still confirms or returns to MENU; a long press from each state resets everything (including the OLED, which a short press does not reset) and causes no extra stage start.
- Board: hold BTNC in MENU, during generation and while playing; the OLED re-initialises and the game returns to MENU each time.

## 2. Larger stages (N = 15, 31 x 31 map)

**Why.** v1.0 stops at N = 10 (a 21 x 21 tile map). A bigger maze is a natural third stage, and it is the base the loops and item boxes below are most interesting on.

**What.**
- Add a stage with N = 15 cells per side, so the tile map is 31 x 31 (`MAP_DIM = 2N + 1`).
- `MAP_DIM`, `MAP_ADDR_W` (9 to 10 bits, 961 tiles) and the centring offset in `maze_ram`, `render`, `ball_physics` and `maze_gen` stop being fixed to 21 and follow the stage. `COORD_W = 5` still holds (largest index 30).
- `maze_gen`: the explicit stack grows from 100 to 225 entries and its pointer from 7 to 8 bits; the cell coordinates stay at 4 bits (0 to 14).
- `menu_ctrl`, `oled_status_text` and `game_cfg` get a third stage entry (the stage list is currently two entries, selected by one bit).

**The map does not fit the screen.** At 16 px per tile a 31-tile map is 496 px, taller than the 480-line picture, and its rotated corners are about 700 px from the centre. The v1.0 map (336 px, about 475 px across the diagonal) fits. Options considered:
- A camera that follows the ball, so only part of the maze is drawn at a time.
- A smaller tile for this stage only. To fit at every angle it would need about 10 px or less, no bigger than the ball (10 px across), and `TILE_SHIFT`, the ball radius and the physics constants are tied to 16 px tiles.
- A tile that is not a power of two (for example 15 px = 465 px). It still clips at 45 degrees (about 658 px across the diagonal), and the tile index would need a divider or a lookup.

**Decided: camera that follows the ball, on N = 15 only.** A locked camera would shake the whole maze on every bounce, so it has a dead zone (about ±48 px) and shift-only smoothing, and it snaps to the ball on a new maze. N = 5 and N = 10 keep the fixed view. The design is in stories 7.2 and 7.3 of `epics-v2.md`. The goal may be off-screen until the ball gets near it.

**Where.** `rtl/labyrinth_pkg.vh`, `rtl/maze_gen.v`, `rtl/maze_ram.v`, `rtl/camera.v` (new), `rtl/render.v`, `rtl/ball_overlay.v`, `rtl/ball_physics.v`, `rtl/menu_ctrl.v`, `rtl/oled_status_text.v`.

**Check.**
- `tb_maze_gen`: N = 15 mazes are perfect and solvable for many seeds; the stack never overflows.
- `tb_render`, `tb_ball_physics`: the existing checks pass at N = 15 (no tunnelling, bounce ratios, goal test).
- Routed build: block RAM, LUT and timing caps still met (AD-8).
- Board: the whole maze is playable, the walls are readable, and the view does not shake when the ball bounces.

## 3. Loops in the maze (HARD and larger only)

**Why.** A perfect maze has exactly one route between any two cells, so the route is easy to find on a small map and offers no choice. Extra openings give alternative routes. EASY stays a perfect maze.

**What.**
- After the depth-first search finishes on the HARD stage and above, remove K interior wall tiles that separate two floor cells. K is fixed per stage in `maze_gen` parameters, not a menu setting: EASY 0, HARD (N = 10) 5, N = 15 7. These are starting values that need playtesting.
- Never remove outer-boundary walls.
- The random choice comes from the same 32-bit LFSR. `maze_gen` stays the only writer of `maze_ram` (AD-5), so the pass lives inside `maze_gen` as an extra phase before it signals done.
- The architecture spine states "perfect maze" as a property (AD-12 area); that text and the tests change to "connected, with K extra openings on loop stages".

**Where.** `rtl/maze_gen.v`, `tb/tb_maze_gen.v`, the architecture spine.

**Check.**
- Testbench: EASY mazes are still perfect; HARD and N = 15 mazes are connected and have exactly (cells - 1 + K) openings, with start and goal reachable, for many seeds and deterministic per seed.
- Physics and render benches are unaffected (they only read the map).
- Board: visible alternative routes on HARD.

## 4. Win screen polish

**Why.** The v1.0 win panel is a static "YOU WIN" and a green border. The finishing time is only on the OLED.

**What.**
- The goal tile blinks (a few Hz, from a frame counter) behind the panel during WIN.
- The panel also shows the finishing time (`mm:ss`), taken from `game_timer`'s BCD outputs.
- Decided: with the countdown (item 5) the panel shows the time left at the win, straight from the timer registers.

**Where.** `rtl/win_overlay.v` (a smaller text row, for example at 4x scale, and the time inputs), `rtl/render.v` (blink flag), `rtl/My_Top_Module.v` (wire the time into `render`).

**Check.**
- Testbench: extend `tb_win_render` with the time glyphs and with the goal blink phase at known frames.
- Board: the time on the panel matches the OLED, and the blink is visible and does not flicker.

## 5. Time limit (every game)

**Why.** The v1.0 timer only counts up. A countdown adds pressure and a way to lose. There is no separate mode: every game has a time limit.

**What.**
- Each maze gets a countdown by stage. Starting values: EASY 60 s, HARD 120 s, N = 15 180 s. These need playtesting and should be parameters.
- The timer counts down in PLAY and replaces the v1.0 count-up (the OLED shows the time left). At 00:00 the game enters a new LOSE state: a "TIME UP" panel on the monitor and on the OLED, held about 2 s, then back to the MENU.
- Winning before 00:00 behaves as today (WIN, then automatic replay with a fresh countdown).
- Plumbing that changes:
  - `game_cfg` stays at 8 bits; there is no mode setting.
  - `game_state` is a full 2-bit encoding (MENU, GENERATE, PLAY, WIN), so adding LOSE needs 3 bits. The state is compared by literal in `My_Top_Module`, `render`, `game_timer` and `oled_status_text`; replace those with shared `localparam`s.
  - `game_timer` changes from count-up to count-down, loaded with the stage's limit at game start. The Story 4.4 tests change to match.

**Where.** `rtl/game_ctrl.v`, `rtl/game_timer.v`, `rtl/oled_status_text.v`, `rtl/win_overlay.v` (or a sibling `lose_overlay`), `rtl/render.v`, `rtl/My_Top_Module.v`.

**Check.**
- Testbench: with a shortened limit, the countdown reaches 00:00 and enters LOSE; reset from LOSE returns to MENU; a win before the limit freezes the remaining time and replays with a fresh countdown.
- Board: EASY and HARD; the countdown matches a watch; the TIME UP screen appears and the game returns to the menu.

## 6. Item boxes (buff and debuff)

**Why.** Item boxes add chance and recovery to a run, in the style of Mario Kart. Rolling the ball onto one gives a random timed effect that changes how the maze feels.

**What.**
- **Two box types.** A buff box (green and blue) and a debuff box (red), each drawn as a distinct tile with a white "?" glyph. Rolling the ball's centre onto a box picks one effect at random from that box's pool (LFSR) and starts it.
- **Effect list (accepted).**
  - Gravity: low gravity (half of g), high gravity (double g), zero gravity (the ball drifts and keeps bouncing, since there is no friction), reverse gravity (the gravity vector is negated).
  - Controls: invert controls (left and right rotation swapped).
  - Visual: fog of war (only tiles within a radius of the ball are drawn).
  - Invincibility (buff box only): debuff boxes are ignored while it lasts. The ball can roll over them, nothing happens, and the box is consumed (it respawns after the normal delay).
  - Time bonus (buff box only): an instant effect with no duration. It adds seconds to the countdown (item 5), capped at the display maximum of 99:59. The amount is a parameter (for example 10 s). It does not replace the active effect, since it has no timer of its own.
- **Pools.** Buff box: low gravity, invincibility, time bonus. Debuff box: reverse gravity, high gravity, zero gravity, invert controls, fog of war.
- **Rejected for now:** checkpoints and trap tiles (dropped from the v2.0 list), speed-cap changes, bounce (restitution) effects, time penalty, teleports, mirror view, fast or slow rotation, ball-size changes, ghost mode and path reveal.
- **Rules.** One effect is active at a time, and a new pickup replaces it. Duration is about 8 s (a parameter, to be playtested). The effect clears on a replay, on reset and on LOSE or WIN.
- **Placement and count.** Each stage has 2 buff boxes and 2 debuff boxes. They sit on floor cells that are not the start or goal cell, and no two boxes share a cell. A box is a pickup, not an obstacle, so it never blocks the route.
- **Respawn.** Boxes respawn. After a pickup the box disappears from its cell and reappears there after a delay (a parameter, for example 15 s; to be playtested). If the ball is on the cell when the delay ends, the box waits until the ball leaves. Each pickup rolls a fresh random effect from that box's pool. Respawn timers clear on a new maze.
- **Owner.** A new `item_ctrl` module is the single owner of the active effect and its remaining time (AD-5). It outputs the effect code to the consumers below.

**How each effect is applied.**
- Gravity: scale the product that `ball_physics` already computes per frame (shift right by one for low, shift left by one for high, zero for zero gravity, negate for reverse). Scaling after the multiply keeps the constant multiply in LUTs and keeps the 5 px/frame speed cap, so the no-tunnelling guarantee stays. The carried fraction bits (the dropped low bits of the product) must be scaled the same way, or the carry goes wrong when an effect starts or ends.
- Invert controls: swap the sign of the rotation command in `angle_rot_cmd` in `My_Top_Module`, for the smooth path and for the snap path (mouse and buttons both).
- Invincibility: while it is active, `item_ctrl` ignores a pickup of a debuff box. Picking up a buff box still works and replaces the current effect (one effect at a time), and picking up a debuff box while invincible neither starts a debuff nor ends the invincibility, and the box is consumed and respawns as if picked up.
- Time bonus: a one-cycle pulse from `item_ctrl` to `game_timer`, which adds seconds to its BCD registers. This is a second timer change after the count-down in item 5, so the two share one design.
- Fog of war: in `render`, blank pixels whose screen distance from the ball exceeds a radius. `ball_overlay` already does a squared-distance test against a radius, so the same structure can be reused.
- OLED roulette: on a pickup the OLED switches to a roulette with no text. The icons of that box's pool cycle in one slot (16 x 16 pixel art drawn at 3x), slow down over about 1.5 s and stop on the item `item_ctrl` already chose; it holds about 1 s, then the effect starts and the OLED returns to the status page. The game keeps running meanwhile, but no box can be picked up until the roulette ends. A debuff box blocked by invincibility gets no roulette; the OLED shows the invincibility icon for about 1 s instead. There is one icon per effect (8 in total), with a green frame for buffs and a red frame for debuffs.
- OLED status page: after the roulette, one line such as `ITEM: LOW GRAV 06` shows the name and the seconds left (`oled_status_text`).

**Where.** `rtl/item_ctrl.v` (new), `rtl/maze_gen.v` and `rtl/maze_ram.v` (placement and storage of the boxes), `rtl/ball_physics.v`, `rtl/render.v`, `rtl/My_Top_Module.v`, `rtl/oled_status_text.v`, a new icon ROM and roulette pixel source for the OLED.

**Check.**
- Testbench, per effect: with low and high gravity the velocity after N frames is half and double the normal value; reverse gravity moves the ball the opposite way; zero gravity leaves the velocity unchanged; invert controls turns left into right in both smooth and snap modes; while invincible, a debuff box does nothing, and once invincibility ends a debuff box works again; a time bonus adds the seconds to the countdown (and a countdown near 00:00 is extended rather than ending the game) and leaves the active effect running; a picked-up box vanishes, reappears after the delay, waits while the ball stands on it, and re-rolls its effect; fog blanks pixels beyond the radius and leaves those inside; each effect ends after its duration and clears on replay and reset; a new pickup replaces the old effect; no wall crossings with any gravity effect (reuse the tunnelling bench).
- Render: the buff box, the debuff box, and the fog edge pixels.
- Board: pick up each effect and watch the behaviour and the OLED countdown.
- Resources: LUT, FF and timing caps still met (AD-8).

## Suggested order and dependencies

1. Item 5's state-encoding cleanup first (shared `localparam`s, 3-bit `game_state`), since it touches many files and every later item adds a state or a config bit.
2. Item 2 (larger stage): settle the camera question before anything else is drawn on the bigger map.
3. Item 3 (loops), then item 6 (item boxes): box placement uses the finished map, and the fog radius needs the final map size.
4. Items 4 and 5 (win polish, time limit) last; item 4 reads the timer that item 5 changes.

## Open questions

- Larger stages: should there be a hint (for example an arrow at the screen edge) when the goal is off-screen? Decide after playing N = 15 on the board.
- Item boxes: the time bonus amount (placeholder 10 s).
- Item boxes: the respawn delay and the effect duration are placeholders (15 s and 8 s) that need playtesting.
