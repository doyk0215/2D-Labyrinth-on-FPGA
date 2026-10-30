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

**Why.** v1.0 stops at N = 10 (a 21 x 21 tile map). A bigger maze is a natural third stage, and it is the base the loops, traps and checkpoints below are most interesting on.

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

## 4. Checkpoints and trap tiles

**Why.** Reaching the goal is the only objective in v1.0. Required waypoints and avoid-these tiles add route planning and risk.

**What.**
- **Checkpoints.** A few floor tiles (for example 2 on HARD and 3 on N = 15; tunable) that the ball must pass through before the goal unlocks. A checkpoint is not a respawn point; it only records "visited".
  - While any checkpoint is unvisited the goal is locked: the goal test (ball centre inside the goal tile) is ignored, and the goal tile is drawn in a locked style (for example dim or hollow), and normally once unlocked.
  - A visited checkpoint changes colour (or disappears) so progress is visible.
  - The visited flags clear on `phys_init`, which also happens on a replay and on reset.
- **Trap tiles.** Floor tiles that send the ball back to the start tile with zero velocity when its centre enters them. The timer keeps running, and visited checkpoints stay visited.
- **Placement (in `maze_gen`, after the maze exists).** Choose dead-end cells (three walls) that are not the start or goal, with no two items on one cell. A dead end is never between two other cells, so no trap can block the route to anything else, and every checkpoint stays reachable. This needs enough dead ends: check the count on EASY, HARD and N = 15, especially after item 3 removes some.
- **Storage.** A few cell-coordinate registers for the checkpoints (like `start_*` and `goal_*` today). The traps could use a second bit plane in `maze_ram` or a short list; decide by resource cost.
- **Detection.** The same "centre inside the tile" test as the goal, evaluated in `ball_physics` once per frame at the end of the step. In `game_ctrl`, `in_goal` is already used only in PLAY; it must also require "all checkpoints visited".
- **OLED.** A progress line such as `CHK 1/3` during play (`oled_status_text`).

**Where.** `rtl/maze_gen.v`, `rtl/maze_ram.v`, `rtl/ball_physics.v`, `rtl/render.v`, `rtl/game_ctrl.v`, `rtl/oled_status_text.v`.

**Check.**
- Testbench: for many seeds every checkpoint and the goal are reachable from the start without crossing a trap; the goal does not win while a checkpoint is unvisited and wins once all are visited; a trap resets the ball but keeps the flags; the flags clear on replay and reset.
- Render: checkpoint, visited checkpoint, trap, locked goal and unlocked goal pixels.
- Board: walk the route, see the goal unlock, hit a trap, see the ball return to the start.

## 5. Win screen polish

**Why.** The v1.0 win panel is a static "YOU WIN" and a green border. The finishing time is only on the OLED.

**What.**
- The goal tile blinks (a few Hz, from a frame counter) behind the panel during WIN.
- The panel also shows the finishing time (`mm:ss`), taken from `game_timer`'s BCD outputs.
- Open: in time-limit mode (item 6), show the time left instead of the elapsed time, or both.

**Where.** `rtl/win_overlay.v` (a smaller text row, for example at 4x scale, and the time inputs), `rtl/render.v` (blink flag), `rtl/My_Top_Module.v` (wire the time into `render`).

**Check.**
- Testbench: extend `tb_win_render` with the time glyphs and with the goal blink phase at known frames.
- Board: the time on the panel matches the OLED, and the blink is visible and does not flicker.

## 6. Time-limit mode

**Why.** The v1.0 timer only counts up. A countdown adds pressure and a way to lose.

**What.**
- A settings-page switch (NORMAL or TIME LIMIT) in `menu_ctrl`, latched at game start like the other settings (AD-5).
- Each maze gets a countdown by stage. Starting values: EASY 60 s, HARD 120 s, N = 15 180 s. These need playtesting and should be parameters.
- The timer counts down in PLAY. At 00:00 the game enters a new LOSE state: a "TIME UP" panel on the monitor and on the OLED, held about 2 s, then back to the MENU.
- Winning before 00:00 behaves as today (WIN, then automatic replay with a fresh countdown).
- Traps do not change the clock (open: a time penalty per trap would be easy to add).
- Plumbing that changes:
  - `game_cfg` has no spare bits (rotation 2, restitution 2, cells 4), so it widens to 9 bits.
  - `game_state` is a full 2-bit encoding (MENU, GENERATE, PLAY, WIN), so adding LOSE needs 3 bits. The state is compared by literal in `My_Top_Module`, `render`, `game_timer` and `oled_status_text`; replace those with shared `localparam`s.
  - `game_timer` gets a down-count mode.

**Where.** `rtl/menu_ctrl.v`, `rtl/game_ctrl.v`, `rtl/game_timer.v`, `rtl/oled_status_text.v`, `rtl/win_overlay.v` (or a sibling `lose_overlay`), `rtl/render.v`, `rtl/My_Top_Module.v`.

**Check.**
- Testbench: with a shortened limit, the countdown reaches 00:00 and enters LOSE; reset from LOSE returns to MENU; a win before the limit freezes the remaining time and replays with a fresh countdown; NORMAL mode is unchanged.
- Board: both modes on EASY and HARD; the countdown matches a watch; the TIME UP screen appears and the game returns to the menu.

## Suggested order and dependencies

1. Item 6's state-encoding cleanup first (shared `localparam`s, 3-bit `game_state`, 9-bit `game_cfg`), since it touches many files and every later item adds a state or a config bit.
2. Item 2 (larger stage): settle the camera question before anything else is drawn on the bigger map.
3. Item 3 (loops), then item 4 (checkpoints and traps): placement needs the final dead-end count, which loops change.
4. Items 5 and 6 (win polish, time-limit mode) last; item 5 reads the timer that item 6 changes.

## Open questions

- Larger stages: camera on the ball, smaller tiles, or a non-power-of-two tile?
- Counts: how many checkpoints and traps per stage, and may EASY have none?
- Does a trap cost time in time-limit mode?
- Does the win panel show elapsed time or time left in time-limit mode?
- Loop density K: fixed per stage, or a settings option?
