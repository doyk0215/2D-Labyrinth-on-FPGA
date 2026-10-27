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

## 3. Interface contract (v1.0, frozen)

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
- 441 one-bit tiles, address `addr[8:0] = row*21 + col`, 1 = wall
- Write port (A, `maze_gen` only): `we`, `waddr[8:0]`, `wdata`
- Read port 1 (A, physics): `raddr_p[8:0]` → `rdata_p`, 1-clock read latency
- Read port 2 (C, render): `raddr_r[8:0]` → `rdata_r`, 1-clock read latency
- Maze outputs of `maze_gen` (held until the next generation): `start_col[4:0]`, `start_row[4:0]`, `goal_col[4:0]`, `goal_row[4:0]`
- Maze placement (added 2026-10-24, with `maze_gen`): an N-cell maze (N = 2..10) is stored **centred** in the 21×21 map, filling tiles `10-N .. 10+N` in each axis; all other tiles are wall. The middle of every maze is therefore tile 10, so the renderer and physics always rotate about the map centre (336 px / 2 = 168 px) and never need `n_cells` for centring. `start_*`/`goal_*` are absolute tile coordinates in the 21×21 map: start = `(9+N, 9+N)` (bottom-right cell, drawn green, the ball spawns here), goal = `(11-N, 11-N)` (top-left cell, drawn red).
- Start/goal swap (team decision 2026-10-28, implemented): until then the start was top-left and the goal bottom-right. Commit 4b1fb42 had moved the spawn to the bottom-right by placing the ball on `goal_*`, which would win at once under the AD-11 goal test; `maze_gen` now swaps the two assignments and `ball_physics` spawns on `start_*`.

**Maze generation (A)**
- Inputs: `gen_start` (pulse), `n_cells[3:0]` (from `game_cfg`), `seed[31:0]`
- Outputs: `gen_busy`, `gen_done` (pulse)

**Ball physics (A)**
- Inputs: `phys_init` (pulse: place ball at the start tile, zero velocity), `phys_en` (level: PLAY state), `frame_tick`, `angle`, `sin_q`, `cos_q`, `restitution_sel[1:0]`, `start_col/row`, `goal_col/row`, maze read port 1
- Outputs: `ball_x[17:0]`, `ball_y[17:0]` (signed Q9.8, maze pixels from the maze centre), `in_goal` (level), `phys_done` (pulse; must occur inside the blanking interval, NFR2)
- Story 3.1 as built: `ball_physics` takes `sin_q`/`cos_q` (not `angle`), has no maze port or `restitution_sel` yet (Story 3.2), and also outputs `vel_x`/`vel_y` (Q4.8). Gravity is `g·(sin, cos)` in the maze frame; the current requested tuning uses `g = 0.15 px/frame²` with fractional carry and a 5 px/frame per-axis cap. Until walls exist the ball stops at the map edge. `ball_overlay` (new) turns the maze position into a screen position and a per-pixel `ball_on`, which `render` draws (new input `ball_on`, one clock behind `pixel_x/y` like render's own flags).

**Game control (B)**
- `game_state[1:0]`: 0 MENU, 1 GENERATE, 2 PLAY, 3 WIN
- Outputs: `gen_start`, `phys_init`, `phys_en`, `game_state`
- Inputs: `gen_done`, `in_goal`, reset, `game_cfg` (from `menu_ctrl`)

**Menu and OLED (B and A)**
- `game_cfg` — `n_cells[3:0]`, `restitution_sel[1:0]`, `rot_speed_sel[1:0]` — `menu_ctrl` → `game_ctrl` (latched at game start)
- `status_text[511:0]` — 64 characters (4 rows × 16), row-major, ASCII — `menu_ctrl` → `oled_driver`
- `oled_driver` pins: `oled_cs`, `oled_mosi`, `oled_sclk`, `oled_dc`, `oled_res`, `oled_vbatc`, `oled_vddc`

**Render (C)**
- Inputs: `angle`, `sin_q`, `cos_q`, `ball_x`, `ball_y`, `game_state`, `start/goal` (absolute tile coordinates), maze read port 2 (no `n_cells`: the maze is always centred in the map)
- Outputs: `vga_r/g/b[3:0]`, `vga_hs`, `vga_vs`
- C latches `angle`, `ball_x`, `ball_y` at frame start (AD-6)

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

- DY holds the Basys 3, the Pmod OLED and the VGA display, and runs every integration check (end of week 1, end of week 2, final).
- QZ and CJX verify with simulation and testbenches (AD-13) and hand over a branch that builds in Vivado 2025.2 with no errors and passes its testbenches.
- Hardware checks for a story are requested from DY with the branch name and the story number; DY reports PASS/FAIL back with a photo or note.
- Still to confirm: who has the PS/2-capable USB mouse and the VGA-to-HDMI converter (needed from Story 1.1 and Story 2.1 onwards).

## 6. Open points for the kickoff

1. ~~Confirm the interface proposal in section 3~~ — done, agreed by all three.
2. Who covers Story 2.3 (CJX's) if it slips. Streams are assigned: A = DY, B = QZ, C = CJX.
3. Which of 5.2–5.4 each person takes.
4. The course's open constraint questions (for example, IP cores allowed?) from the PRD.
