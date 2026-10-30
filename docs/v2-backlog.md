# v2.0 Backlog — 2D Labyrinth on FPGA

Features deferred past the graded v1.0 build. Each entry says why it came up, what it should do, and how to check it. Story details for v1.0 stay in `_bmad-output/planning-artifacts/epics.md`.

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

**Problem to settle first: the map does not fit the screen.** At 16 px per tile a 31-tile map is 496 px, taller than the 480-line picture, and its rotated corners are about 700 px from the centre. The v1.0 map (336 px, about 475 px across the diagonal) fits. Options:
- A camera that stays centred on the ball, so only part of the maze is drawn at a time (changes `render`'s centre offset, and the start and goal may be off-screen).
- A smaller tile for this stage only (for example 8 px, so 248 px). `TILE_SHIFT`, the ball radius (5 px) and the physics constants are tied to 16 px tiles, so this is a larger change.
- A tile that is not a power of two (for example 14 px = 434 px). The tile index would need a divider or a lookup.

**Where.** `rtl/labyrinth_pkg.vh`, `rtl/maze_gen.v`, `rtl/maze_ram.v`, `rtl/render.v`, `rtl/ball_physics.v`, `rtl/menu_ctrl.v`, `rtl/oled_status_text.v`.

**Check.**
- `tb_maze_gen`: N = 15 mazes are perfect and solvable for many seeds; the stack never overflows.
- `tb_render`, `tb_ball_physics`: the existing checks pass at N = 15 (no tunnelling, bounce ratios, goal test).
- Routed build: block RAM, LUT and timing caps still met (AD-8).
- Board: the whole maze is playable and the start, goal and walls are readable.

## 3. Loops in the maze (HARD and larger only)

**Why.** A perfect maze has exactly one route between any two cells, so the route is easy to find on a small map and offers no choice. Extra openings give alternative routes. EASY stays a perfect maze.

**What.**
- After the depth-first search finishes on the HARD stage and above, remove K interior wall tiles that separate two floor cells. K is a parameter (for example about N / 2); it needs playtesting.
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
- Open: in time-limit mode (item 5), show the time left instead of the elapsed time, or both.

**Where.** `rtl/win_overlay.v` (a smaller text row, for example at 4x scale, and the time inputs), `rtl/render.v` (blink flag), `rtl/My_Top_Module.v` (wire the time into `render`).

**Check.**
- Testbench: extend `tb_win_render` with the time glyphs and with the goal blink phase at known frames.
- Board: the time on the panel matches the OLED, and the blink is visible and does not flicker.

## 5. Time-limit mode

**Why.** The v1.0 timer only counts up. A countdown adds pressure and a way to lose.

**What.**
- A settings-page switch (NORMAL or TIME LIMIT) in `menu_ctrl`, latched at game start like the other settings (AD-5).
- Each maze gets a countdown by stage. Starting values: EASY 60 s, HARD 120 s, N = 15 180 s. These need playtesting and should be parameters.
- The timer counts down in PLAY. At 00:00 the game enters a new LOSE state: a "TIME UP" panel on the monitor and on the OLED, held about 2 s, then back to the MENU.
- Winning before 00:00 behaves as today (WIN, then automatic replay with a fresh countdown).
- Plumbing that changes:
  - `game_cfg` has no spare bits (rotation 2, restitution 2, cells 4), so it widens to 9 bits.
  - `game_state` is a full 2-bit encoding (MENU, GENERATE, PLAY, WIN), so adding LOSE needs 3 bits. The state is compared by literal in `My_Top_Module`, `render`, `game_timer` and `oled_status_text`; replace those with shared `localparam`s.
  - `game_timer` gets a down-count mode.

**Where.** `rtl/menu_ctrl.v`, `rtl/game_ctrl.v`, `rtl/game_timer.v`, `rtl/oled_status_text.v`, `rtl/win_overlay.v` (or a sibling `lose_overlay`), `rtl/render.v`, `rtl/My_Top_Module.v`.

**Check.**
- Testbench: with a shortened limit, the countdown reaches 00:00 and enters LOSE; reset from LOSE returns to MENU; a win before the limit freezes the remaining time and replays with a fresh countdown; NORMAL mode is unchanged.
- Board: both modes on EASY and HARD; the countdown matches a watch; the TIME UP screen appears and the game returns to the menu.

## 6. Item boxes (buff and debuff)

**Why.** Item boxes add chance and recovery to a run, in the style of Mario Kart. Rolling the ball onto one gives a random timed effect that changes how the maze feels.

**What.**
- **Two box types.** A buff box (green and blue) and a debuff box (red), each drawn as a distinct tile with a "?" glyph. Rolling the ball's centre onto a box picks one effect at random from that box's pool (LFSR) and starts it.
- **Effect list (accepted).**
  - Gravity: low gravity (half of g), high gravity (double g), zero gravity (the ball drifts and keeps bouncing, since there is no friction), reverse gravity (the gravity vector is negated).
  - Controls: invert controls (left and right rotation swapped).
  - Visual: fog of war (only tiles within a radius of the ball are drawn).
  - Invincibility (buff box only): debuff boxes are ignored while it lasts. The ball can roll over them and nothing happens.
  - Time bonus (buff box only): an instant effect with no duration. In time-limit mode (item 5) it adds seconds to the countdown; in normal mode it takes the same number of seconds off the elapsed time (never below 00:00). The amount is a parameter (for example 10 s). It does not replace the active effect, since it has no timer of its own.
- **Pools.** Buff box: low gravity, invincibility, time bonus. Debuff box: reverse gravity, high gravity, zero gravity, invert controls, fog of war.
- **Rejected for now:** checkpoints and trap tiles (dropped from the v2.0 list), speed-cap changes, bounce (restitution) effects, time penalty, teleports, mirror view, fast or slow rotation, ball-size changes, ghost mode and path reveal.
- **Rules.** One effect is active at a time, and a new pickup replaces it. Duration is about 8 s (a parameter, to be playtested). The effect clears on a replay, on reset and on LOSE or WIN.
- **Placement and count.** Each stage has 2 buff boxes and 2 debuff boxes. They sit on floor cells that are not the start or goal cell, and no two boxes share a cell. A box is a pickup, not an obstacle, so it never blocks the route.
- **Respawn.** Boxes respawn. After a pickup the box disappears from its cell and reappears there after a delay (a parameter, for example 15 s; to be playtested). If the ball is on the cell when the delay ends, the box waits until the ball leaves. Each pickup rolls a fresh random effect from that box's pool. Respawn timers clear on a new maze.
- **Owner.** A new `item_ctrl` module is the single owner of the active effect and its remaining time (AD-5). It outputs the effect code to the consumers below.

**How each effect is applied.**
- Gravity: scale the product that `ball_physics` already computes per frame (shift right by one for low, shift left by one for high, zero for zero gravity, negate for reverse). Scaling after the multiply keeps the constant multiply in LUTs and keeps the 5 px/frame speed cap, so the no-tunnelling guarantee stays. The carried fraction bits (the dropped low bits of the product) must be scaled the same way, or the carry goes wrong when an effect starts or ends.
- Invert controls: swap the sign of the rotation command in `angle_rot_cmd` in `My_Top_Module`, for the smooth path and for the snap path (mouse and buttons both).
- Invincibility: while it is active, `item_ctrl` ignores a pickup of a debuff box. Picking up a buff box still works and replaces the current effect (one effect at a time), and picking up a debuff box while invincible neither starts a debuff nor ends the invincibility.
- Time bonus: a one-cycle pulse from `item_ctrl` to `game_timer`, which adds seconds (time-limit mode) or subtracts them with a floor at zero (normal mode) in its BCD registers. This is a second timer change after the down-count mode in item 5, so the two share one design.
- Fog of war: in `render`, blank pixels whose screen distance from the ball exceeds a radius. `ball_overlay` already does a squared-distance test against a radius, so the same structure can be reused.
- OLED: one line such as `ITEM: LOW GRAV 06` showing the name and the seconds left (`oled_status_text`).

**Where.** `rtl/item_ctrl.v` (new), `rtl/maze_gen.v` and `rtl/maze_ram.v` (placement and storage of the boxes), `rtl/ball_physics.v`, `rtl/render.v`, `rtl/My_Top_Module.v`, `rtl/oled_status_text.v`.

**Check.**
- Testbench, per effect: with low and high gravity the velocity after N frames is half and double the normal value; reverse gravity moves the ball the opposite way; zero gravity leaves the velocity unchanged; invert controls turns left into right in both smooth and snap modes; while invincible, a debuff box does nothing, and once invincibility ends a debuff box works again; a time bonus adds the seconds to the countdown in time-limit mode (and a countdown near 00:00 is extended rather than ending the game), takes them off the elapsed time in normal mode with a floor at 00:00, and leaves the active effect running; a picked-up box vanishes, reappears after the delay, waits while the ball stands on it, and re-rolls its effect; fog blanks pixels beyond the radius and leaves those inside; each effect ends after its duration and clears on replay and reset; a new pickup replaces the old effect; no wall crossings with any gravity effect (reuse the tunnelling bench).
- Render: the buff box, the debuff box, and the fog edge pixels.
- Board: pick up each effect and watch the behaviour and the OLED countdown.
- Resources: LUT, FF and timing caps still met (AD-8).

## Suggested order and dependencies

1. Item 5's state-encoding cleanup first (shared `localparam`s, 3-bit `game_state`, 9-bit `game_cfg`), since it touches many files and every later item adds a state or a config bit.
2. Item 2 (larger stage): settle the camera question before anything else is drawn on the bigger map.
3. Item 3 (loops), then item 6 (item boxes): box placement uses the finished map, and the fog radius needs the final map size.
4. Items 4 and 5 (win polish, time-limit mode) last; item 4 reads the timer that item 5 changes.

## Open questions

- Larger stages: camera on the ball, smaller tiles, or a non-power-of-two tile?
- Does the win panel show elapsed time or time left in time-limit mode?
- Loop density K: fixed per stage, or a settings option?
- Item boxes: the buff pool has three effects (low gravity, invincibility, time bonus) and the debuff pool has five. Is that split intended?
- Item boxes: the time bonus amount (placeholder 10 s), and whether it should work in normal mode (as written, it takes seconds off the elapsed time) or be left out of the pool there.
- Item boxes: when invincibility ignores a debuff box, does the box stay in place (still there to be hit later) or is it consumed and respawned as if picked up?
- Item boxes: the respawn delay and the effect duration are placeholders (15 s and 8 s) that need playtesting.
- Item boxes: the debuff box is red and the buff box green and blue, while the start tile is red and the goal tile is green. Use a "?" glyph or a pattern so boxes are not confused with them.
