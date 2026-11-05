# Parallel Workstreams — 2D Labyrinth on FPGA

Version 1.0 (2026-10-23), agreed by DY, QZ and CJX. Based on `epics.md`, the architecture spine (AD-1 to AD-13) and the PRD. The interface contract in section 3 is frozen: changes need all three owners to approve and a pull request that updates this file.

## 1. Stream ownership

| Stream | Owns (files in `rtl/` and `tb/`) | Stories |
| --- | --- | --- |
| **A (DY). Physics engine and maze generation** | `ball_physics`, `maze_gen`, `sincos_rom`, `oled_driver`, `font_rom` | 3.1, 3.2, 1.3, 4.1, 2.2 (sine/cosine table part) |
| **B (QZ). Input and game control** | `MouseCtl` (course-supplied) wiring, `input_mux`, angle accumulator, `game_ctrl`, `menu_ctrl` | 2.1, 2.2 (angle part), 1.4, 3.3 (control part), 3.4, 4.2, 4.3, 4.4 |
| **C (CJX). Graphics** | `vga_timing`, `render`, `maze_ram`, `My_Top_Module.v`, `constraints/basys3.xdc` | 1.1, 1.2, 2.3, 2.4, 3.3 (win indication), 5.1 |
| **Shared** | `labyrinth_pkg.vh` (owner: DY; changes need all three owners to approve) | 5.2 (regression), 5.3 (demo), 5.4 (report) |

Rough effort (1–5 per story, estimate): A ≈ 17, B ≈ 15, C ≈ 15.

Owners: A = DY, B = QZ, C = CJX.

Rules:
- One owner per file (this follows AD-5, single writer). Others ask the owner or open a change request.
- `My_Top_Module.v` and the XDC belong to C. A and B send C their module ports and pin needs.
- All work happens on feature branches (`feature/<story>-<name>`) and reaches `main` only through a pull request that the owner of the touched interface reviews. See `docs/work-order.md`, "Git workflow".

**Step 0 is complete** (done by DY, 2026-10-23): `rtl/labyrinth_pkg.vh`, the folder layout, `constraints/basys3.xdc` and `scripts/create_project.tcl`. Story 1.1 starts from these; CJX should pull them, run `scripts/create_project.tcl` in Vivado 2025.2, verify the XDC pins against Digilent's master XDC, and continue with `My_Top_Module.v` and `vga_timing`.

## 2. Work order within each stream

**A:** (1) `sincos_rom` and testbench, as B and C need the trig values; (2) `oled_driver` + `font_rom` (4.1), since B's menu stories wait on it; (3) `maze_gen` (1.3); (4) `ball_physics` (3.1, then 3.2).
**B:** (1) mouse (`MouseCtl`) + `input_mux` (2.1); (2) angle accumulator (2.2); (3) `game_ctrl` skeleton (1.4); (4) win/reset flow (3.3, 3.4); (5) `menu_ctrl` stories (4.2–4.4) once A's 4.1 is merged.
**C:** (1) Story 1.1 first — the Vivado project, XDC, `labyrinth_pkg.vh`, `vga_timing`, and a test pattern, within the first two days because it unblocks integration; (2) `maze_ram` + fixed maze render (1.2); (3) rotated render (2.3), the riskiest story, so start it as early as possible; (4) 2.4, win indication, timing closure.

Until C's project skeleton lands, A and B work in simulation only, against stubs of the other modules.

## 3. Interface contract (v1.0, with Story 6.1 state extension)

Widths and scales follow AD-4. All signals are in the single 100 MHz clock domain (AD-2) and synchronous to `clk`. Active-high, one-cycle pulses unless stated.

**Global (from C's `vga_timing`)**
- `clk` (100 MHz), `rst` (synchronous, active-high)
- `ce_pix` — 1-in-4 enable
- `frame_tick` — pulse at start of vertical blanking

**Rotation**
- `rot_cmd[1:0]` signed: −1 / 0 / +1 — B (`input_mux`) → B (angle)
- `angle[11:0]` — unsigned, 4096 = 360° — B (angle accumulator) → A, C
- `sincos_rom`: input `angle[11:0]`; outputs `sin_q[15:0]`, `cos_q[15:0]` (signed Q1.14), latency 1 clock — A → A, C

**Maze memory (`maze_ram`, owned by C)**
- 1,024 one-bit tiles (32 × 32), address `addr[9:0] = {row[4:0], col[4:0]}`, 1 = wall (Story 7.1). Every stage uses this fixed 32-tile row, so no module multiplies to find a tile; the largest stage (N = 15) uses rows and columns 0..30.
- Write port (A, `maze_gen` only): `we`, `waddr[9:0]`, `wdata`
- Read port 1 (A, physics): `raddr_p[9:0]` → `rdata_p`, 1-clock read latency
- Read port 2 (C, render): `raddr_r[9:0]` → `rdata_r`, 1-clock read latency
- Maze outputs of `maze_gen` (held until the next generation): `start_col[4:0]`, `start_row[4:0]`, `goal_col[4:0]`, `goal_row[4:0]`
- Maze placement (Story 7.1, replacing the v1 centred 21×21 layout): an N-cell maze (N = 2..15) fills tiles 0..2N in each axis from the top-left; every other stored tile is wall. The map centre is tile N (pixel 16N + 8), so `render` and `ball_physics` take `n_cells` to centre the view and the ball position. `start_*`/`goal_*` are tile coordinates from the top-left: start = `(2N-1, 2N-1)` (bottom-right cell, drawn red, the ball spawns here), goal = `(1, 1)` (top-left cell, drawn green).

**Maze generation (A)**
- Inputs: `gen_start` (pulse), `n_cells[4:0]` (from `game_cfg`), `seed[31:0]`
- Outputs: `gen_busy`, `gen_done` (pulse)

**Ball physics (A)**
- Inputs: `phys_init` (pulse: place ball at the start tile, zero velocity), `phys_en` (level: PLAY state), `frame_tick`, `angle`, `sin_q`, `cos_q`, `restitution_sel[1:0]`, `start_col/row`, `goal_col/row`, maze read port 1
- Outputs: `ball_x[17:0]`, `ball_y[17:0]` (signed Q9.8, maze pixels from the maze centre), `in_goal` (level), `phys_done` (pulse; must occur inside the blanking interval, NFR2)
- Story 3.1 as built: `ball_physics` takes `sin_q`/`cos_q` (not `angle`), has no maze port or `restitution_sel` yet (Story 3.2), and also outputs `vel_x`/`vel_y` (Q4.8). Gravity is `g·(sin, cos)` in the maze frame; the current requested tuning uses `g = 0.15 px/frame²` with fractional carry and a 5 px/frame per-axis cap. Until walls exist the ball stops at the map edge. `ball_overlay` (new) turns the maze position into a screen position and a per-pixel `ball_on`, which `render` draws (new input `ball_on`, one clock behind `pixel_x/y` like render's own flags).

**Game control (B)**
- `game_state[2:0]` (Story 6.1): shared `GAME_STATE_W=3` and `ST_*`
  definitions in `rtl/labyrinth_pkg.vh`: MENU=0, GENERATE=1, PLAY=2,
  WIN=3, LOSE=4. Story 8.2 enters LOSE on countdown expiry, holds it for `LOSE_HOLD_FRAMES` (default 120), then returns to MENU. Timeout has priority over a simultaneous goal or regeneration request.
  Declare state ports with `GAME_STATE_W` and use `ST_*` for comparisons and
  case labels. This interface extension requires all three owners' approval.
- Outputs: `gen_start`, `phys_init`, `phys_en`, `game_state`
- Story 8.2 adds `game_ctrl.time_up` from `game_timer`. The timer loads EASY/HARD/HUGE limits (60/120/180 s parameters) on `phys_init` using `n_cells`, counts down only in PLAY, saturates at zero and freezes in WIN/LOSE. Legacy `elapsed_*_bcd` ports now carry remaining time. `time_up` includes the clock edge that decrements 00:01 to zero, so an exactly coincident goal cannot win at the deadline. No division is synthesized: parameter limits are converted to BCD at elaboration.
- In LOSE physics is disabled and both smooth and queued snap rotation are frozen. A short or full CENTER reset still returns to MENU. Story 8.3 shows a dedicated OLED TIME UP / TIME 00:00 page with the active stage and automatic-menu hint; the existing OLED mailbox still switches text only at its own frame boundary.
- Inputs: `gen_done`, `in_goal`, reset, `game_cfg` (from `menu_ctrl`)

**Board switches (Story 9.2 control remap, moved for the CUSTOM stage)**
- `SW15` selects snap rotation (1 = 90-degree press/release steps, 0 = smooth).
- `SW14` selects fixed-seed maze generation (1 = repeatable map, 0 = fresh seed).
- `SW[3:0]` is the CUSTOM stage offset X; its maze size is N = 5 + X (5..20). `SW4` is unused. Legacy auto-start builds use the same mapping.
- The menu stages are EASY (N = 5), MEDIUM (N = 10), HARD (N = 15), EPIC (N = 20), and CUSTOM (N = 5 + SW[3:0]).
- The independent OLED bring-up top keeps its own SW0 text/test-pattern selector.

**CENTER and reset (Story 6.2)**
- `centre_button` synchronizes/debounces BTNC. `short_press` is a one-clock
  pulse on release of a short press. `full_reset` is a level after
  `LONG_PRESS_CYCLES` of debounced hold (default 200,000,000 clocks, about 2 s)
  and remains asserted until debounced release. A long hold never emits short.
- The detector resets only on power-on reset, so its own full reset cannot
  re-arm it while CENTER remains held.
- `system_reset = por_reset | full_reset` clears menu preferences, input
  filters, and both OLED text-mailbox endpoints, and restarts OLED power/init.
  `rst = system_reset | game_reset_request` also resets the existing game,
  angle, physics, generator, timer, seed, and mouse paths. A short gameplay
  reset retains menu preferences and keeps the OLED running, as before.
- `game_ctrl.full_reset` is a synchronous level that resets all controller
  state and selects MENU even with the legacy `START_IN_MENU=0` debug option.
  Ordinary `rst` retains that option's original behavior.
- OLED reset asserts asynchronously and releases through two flip-flops in
  the free-running 6.25 MHz OLED clock domain. Its clock divider is not reset.
  The supplied `Oled_Display` and PS/2 VHDL sources remain unchanged.

**Menu and OLED (B and A)**
- `game_cfg[9:0]` — `{custom, rot_speed_sel[1:0], restitution_sel[1:0], n_cells[4:0]}` — `menu_ctrl` → `game_ctrl` (latched at game start).
- `menu_ctrl.selected_stage` is three bits for EASY (N=5), MEDIUM (N=10), HARD (N=15), EPIC (N=20), and CUSTOM. UP/DOWN move through this order with wrap; both together do nothing. The four-row OLED stage list scrolls its visible window as needed. EPIC has its own HIGH score; CUSTOM does not. PLAY/WIN identify the four presets as `STAGE 1 EASY` through `STAGE 4 EPIC`.
- CUSTOM computes N = 5 + unsigned SW[3:0] and displays the current result as `CUSTOM 5+X=N`; SW4 is unused. Its supported range is 5..20. Time is 12 s × N for custom sizes, with preset limits at N=5/10/15/20. Loop caps remain 3 at N=10 and 5 at N=15; only N=20 increases to a maximum of 7, with each band still seed-skippable. Item boxes: N<=6 has none; N=7..8 has one buff and one debuff; N=9..14 has two of each; N=15..19 has three of each; N=20 has four of each.
- `status_text[511:0]` — 64 characters (4 rows × 16), row-major, ASCII — `menu_ctrl` → `oled_driver`
- `oled_driver` pins: `oled_cs`, `oled_mosi`, `oled_sclk`, `oled_dc`, `oled_res`, `oled_vbatc`, `oled_vddc`

**Item pickup/effects (B, Story 9.2)**
- `maze_gen` holds eight packed tile positions (`box_cols[47:0]`, `box_rows[47:0]`,
  six bits per slot) and `box_valid[7:0]`. The first half are buffs; the second half debuffs. N=20 has four of each; lower sizes keep their existing counts.
- `item_ctrl` owns `box_visible[7:0]`, `active_effect[3:0]`, remaining whole
  seconds `[6:0]`, and per-box respawn counters. It samples the full signed
  Q9.8 ball centre on `phys_done`; no radius/edge contact pickup is used.
- Visibility changes on `phys_init`/`phys_done` in blanking (plus reset/menu
  clearing). Each pickup hides one box for 15 s by default; an occupied box
  waits for departure before reappearing. New maze/reset clears all state;
  WIN/LOSE clears effects/timers and preserves the frozen box picture.
- Effect IDs 0..7 match `item_icon_rom`: LOW_GRAV, INVINCIBLE, TIME_BONUS,
  REVERSE_GRAV, HIGH_GRAV, ZERO_GRAV, INVERT, FOG. `ITEM_NONE=15`.
  Buff/debuff selection uses separate rejection-sampled xorshift32 candidates.
- Full pools are selected in 9.2. Story 9.5 adds INVINCIBLE and instant
  TIME_BONUS; other gravity/control/render consumers arrive in 9.3/9.4.
  9.7 adds roulette blocking/delayed activation (details below).
- `ball_physics.effect_code[3:0]` is sampled with trig per frame. LOW_GRAV
  halves the full signed acceleration product before fraction accumulation;
  carried residual stays in common Q units, with the existing speed cap.
- `oled_status_text` receives active effect/seconds and uses an exactly
  16-character PLAY row (e.g. `ITEM:LOW GRAV 08`). Its mailbox stays frame-safe.
- `pickup_pulse`, slot index and selected code expose one event for future
  consumers. `debuff_blocked` accompanies a consumed debuff protected by
  invincibility; `pickup_effect=ITEM_NONE` in that event, and no effect starts.
  Its normal respawn still runs. An ordinary buff replaces/restarts protection;
  TIME_BONUS is the exception and never changes the active effect or its phase.
- `time_bonus_pulse` is a same-edge, one-clock grant from `item_ctrl` to
  `game_timer`, qualified by PLAY, reset, phys_init and accepted pickup. Do not
  derive it from the registered pickup notification: the extra clock could
  lose a pickup at the expiration edge. `My_Top_Module.ITEM_TIME_BONUS_SECONDS`
  defaults to 10; `game_timer.BONUS_SECONDS` clamps to 0..5999. Addition is BCD,
  capped at 99:59 after applying a coincident ordinary countdown tick. A positive
  grant suppresses same-edge `time_up`; zero/negative parameters do not.
  Partial-second phase and first-visible-input arming are preserved.
- Story 9.7 enables `item_ctrl.DEFER_EFFECT` in the shipping top. The engine
  holds `pending_valid/pending_effect`, consumes the box immediately, and blocks
  new pickups while pending or `roulette_busy`. `roulette_commit` applies the
  held selection once, preserving the same-edge bonus/deadline contract.
  Direct module users default to immediate behavior; legacy top fixtures use
  `ITEM_ROULETTE_ENABLE=0` explicitly. No physical switch bypasses roulette.
- `item_roulette` owns animation timing in the system domain: `SPIN_MS=1500`,
  `HOLD_MS=1000`, `BLOCK_MS=1000` (top `ITEM_ROULETTE_*` / `ITEM_BLOCK_ICON_MS`).
  It cycles only that slot's pool with four progressively longer intervals,
  then displays the held chosen ID. CJX's explicit 2026-11-02 playtest decision
  is to activate when the stopped result is first displayed, before its 1 s
  hold ends. This overrides the original hold-end acceptance wording for now;
  revisit the timing in 9.8. Gameplay and existing effect timers keep running.
- A protected debuff produces only the INVINCIBLE icon for 1 s, with no pending
  effect or commit. Pickups stay blocked through both roulette/result hold and
  this notification, until the OLED has returned to status. Reset, phys_init
  and non-PLAY cancel pending work; an effect already activated at spin stop
  follows the usual terminal-state clearing, with no later duplicate grant.
- `oled_roulette_pixel` uses the existing icon ROM at 3x scale: x=24..71,
  y=8..55 in a black 96x64 frame, with one registered-pixel latency.
  The existing held-data text mailbox now carries the source/icon nibble in
  the same request and latches both at `oled_frame_begin`. Applied visual/frame
  feedback returns through a synchronized toggle and held-data capture, qualified
  by an actual driver pixel request (power-up counter boundaries do not count). Thus
  activation waits for the actual selected-result frame; source/icon never
  change inside an OLED frame. Status text continues updating behind the icon.
- Story 9.4: while `item_ctrl.active_effect` (the top's `item_effect`) is `ITEM_INVERT`, the top negates
  `angle_rot_cmd`, so left and right swap for the mouse and the board
  buttons in smooth and snap modes. A snap press held while the effect starts
  or ends changes direction and is cancelled, like an opposite press.
- Story 9.4: `ball_overlay` outputs `fog_clear` (pixel within `FOG_RADIUS`,
  default 48 px, of the ball's screen centre; LUT squares, no DSP) with the
  same one-clock latency as `ball_on`. `render.fog_en` (top:
  `item_effect == ITEM_FOG`) is latched with the frame snapshot; under fog
  every pixel except the ball and `fog_clear` pixels is black. The top's
  `FOG_RADIUS_PX` parameter sets the radius for 9.8 tuning.
- Story 9.4: `oled_status_text` takes the item seconds' tens and units from a
  0..127 lookup table instead of `/10` and `%10` (same text), so no divider
  sits in front of the OLED text mailbox's 512-bit compare.

**Camera (C, Story 7.2)**
- Inputs: `phys_init`, `phys_done`, `n_cells[4:0]`, `ball_x`, `ball_y`
- Outputs: `cam_x[17:0]`, `cam_y[17:0]` (signed Q9.8, maze pixels from the map centre, the ball's format) and `cam_done` (pulse with every new value, two clocks after `phys_done`, so inside vertical blanking)
- `camera` is the only writer of the camera position. It follows the ball with a dead zone (about ±48 px per axis around its target) and `cam += (target - cam) >>> 3`, snaps to the ball one clock after `phys_init`, and is the map centre (0, 0) when `n_cells` < 11, so N = 5 and N = 10 keep the fixed view. Story 7.3: `render` centres the view on the map centre plus the camera, and `ball_overlay` starts on `cam_done` and draws `ball - cam`, so the maze and the ball always use the same camera value.

**Render (C)**
- Inputs: `angle`, `sin_q`, `cos_q`, `ball_x`, `ball_y`, `game_state`, `start/goal` (absolute tile coordinates), maze read port 2, `n_cells` (Story 7.1: the map centre depends on the stage), `cam_x`, `cam_y` (Story 7.3: the screen centre shows the map centre plus the camera; read live, as they change only in vertical blanking)
- Outputs: `vga_r/g/b[3:0]`, `vga_hs`, `vga_vs`
- C latches `angle`, `ball_x`, `ball_y` at frame start (AD-6). Since Story 7.3 the ball is latched by `ball_overlay` on `cam_done`, and `render` reads `cam_x`/`cam_y` live; both rely on the camera changing only in vertical blanking, between the angle snapshot and the first visible line
- Story 3.3 visual part: `render.game_state` consumes the shared state
  contract and snapshots WIN with angle/trig in vertical blanking. WIN adds a
  fixed `YOU WIN` panel and green outline using `win_overlay` and `font_rom`;
  its flags have the same one-clock pixel latency as the renderer. The top
  enables map reads/display in PLAY and WIN, and masks MENU/GENERATE. QZ still
  connects goal detection and supplies the approximately three-second WIN pause.

- Story 8.3: `lose_overlay` draws a white TIME UP title on a dark red panel
  with a red panel/screen outline. Its flags/font output use the same one-clock
  pixel latency as `win_overlay`. `render.lose_frame` is captured with the
  angle/trig/WIN snapshot in vertical blanking and has priority over the ball
  and map. The top enables frozen maze reads/display in LOSE as in WIN, then
  masks them on return to MENU. Existing WIN glyphs/timing are unchanged.
  No module port widths or state encodings change.

## 4. Dependencies and integration points

| Stream waits on | For |
| --- | --- |
| C (story 1.1) | Vivado project, XDC, package file, `vga_timing`/`frame_tick` for all hardware testing |
| A (`sincos_rom`) | B's angle→rotation check and C's rotated render |
| A (story 4.1) | B's `menu_ctrl` stories 4.2–4.4 |
| A (`maze_gen`) | C's render of random mazes (until then C uses the hard-coded maze) |
| B (`game_ctrl`, angle) | A's physics on hardware; C's rotation on hardware |

**Integration 1 (end of week 1):** video + mouse + angle + generator + OLED text each work on the board. Merge to `main`.
**Integration 2 (end of week 2):** physics + game flow + rotated render together; ball plays on the board. Fallback: snap rotation (Story 2.4).
**Week 3:** OLED menu, polish, timing closure, regression, demo, report.

## 5. Hardware and integration ownership

*(This section is the v1.0 arrangement. For v2.0, board checks follow section 7.3.)*

- DY holds the Basys 3, the Pmod OLED and the VGA display, and runs every integration check (end of week 1, end of week 2, final).
- QZ and CJX verify with simulation and testbenches (AD-13) and hand over a branch that builds in Vivado 2025.2 with no errors and passes its testbenches.
- Hardware checks for a story are requested from DY with the branch name and the story number; DY reports PASS/FAIL back with a photo or note.
- Still to confirm: who has the PS/2-capable USB mouse and the VGA-to-HDMI converter (needed from Story 1.1 and Story 2.1 onwards).

## 6. Open points for the kickoff

1. ~~Confirm the interface proposal in section 3~~ — done, agreed by all three.
2. Who covers Story 2.3 (CJX's) if it slips. Streams are assigned: A = DY, B = QZ, C = CJX.
3. Which of 5.2–5.4 each person takes.
4. The course's open constraint questions (for example, IP cores allowed?) from the PRD.

## 7. v2.0 ownership (from 2026-10-31)

For v2.0 each person takes a different stream from v1, so everyone works across the design and the stories depend on each other's modules. The stories are in `_bmad-output/planning-artifacts/epics-v2.md` and GitHub issues #51 to #68.

### 7.1 Streams and files

| Person | v1.0 stream | v2.0 stream | Owns (files in `rtl/` and `tb/`) |
| --- | --- | --- | --- |
| QZ | B (input and game control) | A (physics, maze generation, OLED driver) | `ball_physics`, `maze_gen`, `sincos_rom`, `oled_driver`, `font_rom`; new: OLED roulette pixel source |
| CJX | C (graphics) | B (input and game control) | `MouseCtl` wiring, `input_mux`, `angle_accumulator`, `game_ctrl`, `menu_ctrl`, `game_timer`, `oled_status_text`; new: `item_ctrl` |
| DY | A (physics engine) | C (graphics and top level) | `vga_timing`, `render`, `maze_ram`, `ball_overlay`, `My_Top_Module.v`, `constraints/basys3.xdc`; new: `camera`, item icon ROM |
| Shared | | | `labyrinth_pkg.vh` (owner: DY; changes need all three owners to approve) |

Files not named above follow their stream: `Oled_Display`, `oled_text_pixel`, `oled_xy`, `oled_clk_div` and `seed_source` go with QZ; `win_overlay` and `lose_overlay` go with DY.

The v1.0 rules still hold: one owner per file (AD-5), feature branches, and a pull request reviewed by the owner of the touched interface. A story that touches a file of another person is paired: the second owner writes their own file and reviews the rest.

For v2.0, add one more rule: the previous owner of a file reviews every pull request that touches it, because they know it best.

### 7.2 Stories and order of work

| Step | Start these in parallel | Waits for |
| --- | --- | --- |
| 1 | QZ: 7.1. CJX: 6.1, then 6.2. DY: 8.1, then 9.6. | nothing |
| 2 | QZ: 7.5. DY: 7.2, then 7.3. CJX: 8.2. | 7.5 and 7.2 need 7.1; 8.2 needs 6.1 |
| 3 | DY: 9.1 (QZ writes the `maze_gen` placement). CJX: 8.3 (DY draws the monitor panel). | 9.1 needs 7.5; 8.3 needs 8.2 |
| 4 | CJX: 9.2 first, then 7.4 when it fits. | 9.2 needs 9.1; 7.4 needs 7.3 |
| 5 | QZ: 9.3, then 9.7 (CJX adds the `item_ctrl` hook). DY: 9.4 (CJX adds invert controls), then 9.5. | 9.3, 9.4, 9.7 and 9.5 need 9.2; 9.7 also needs 9.6; 9.5 also needs 8.2 |
| 6 | All: 9.8 board playtest and tuning. | 9.3, 9.4, 9.5, 9.7 |

The critical path is 7.1, 7.5, 9.1, 9.2, then 9.3 and 9.7, then 9.8. Stories on it come before anything else that is ready. If 7.5 finishes before 7.3, DY starts 9.1 first. Stories 6.2, 8.1 and 9.6 need nothing and can go in whenever there is a gap. If QZ falls behind on 9.3 and 9.7, CJX (free after 9.2) takes more of 9.7.

### 7.3 Board checks

Everyone has access to the Basys 3 and may run a board check and record PASS or FAIL. For v2.0:

- The author of a story does not run its board check. Another person runs it and records PASS or FAIL, with the branch name, the story number and a photo or note, on the story's pull request.
- Anyone may approve a pull request after its board check passes, except its author.
- Integration checks (the end of each step in 7.2 and the final run in 9.8) are done by whoever is free, and the result is posted on the issue.
