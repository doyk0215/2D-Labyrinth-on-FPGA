---
story_id: 1.4
story_key: 1-4-game-state-skeleton-and-regenerate-on-demand
title: Game state skeleton and regenerate on demand
status: review
owner: QZ
epic: 1
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/15
---

# Story 1.4: Game state skeleton and regenerate on demand

As the examiner,
I want to press a button to get a new random maze,
So that I can see that mazes differ and the flow is controlled by one state machine.

## Acceptance Criteria

1. **Game-state flow**
   - `game_ctrl` implements the architecture states `MENU=2'b00`, `GENERATE=2'b01`, `PLAY=2'b10`, and `WIN=2'b11`.
   - With the menu not yet integrated, reset release starts one maze generation and the controller enters `PLAY` only after `gen_done`; the `MENU` state remains defined for Epic 4.
   - `gen_start` is a one-cycle request per generation. Generation does not restart while `gen_busy` is asserted.
   - State changes that affect the displayed frame are synchronized to `frame_tick` (AD-6).

2. **Regenerate on demand**
   - In `PLAY`, a synchronized one-cycle press of the temporary regenerate button (`BTND`) requests a new maze and returns the controller to `GENERATE`.
   - Button presses during `GENERATE` do not queue duplicate generation requests.
   - Each non-debug generation captures a fresh seed before `gen_start`; `sw[0]` debug-fixed mode continues to reproduce the same maze for a fixed size and seed.
   - A later generation with the same size in non-debug mode produces a different map from the previous generation.

3. **Safe handoff between generation and rendering**
   - While the maze is being written, the renderer does not read or consume the partially written map. Gate the maze render read port during `GENERATE` and show the background while the map is unavailable.
   - Keep rendering disabled until `gen_done` has been observed and the controller reaches a frame boundary to enter `PLAY`.
   - Once in `PLAY`, the monitor shows the completed new maze with its distinct start and goal.

4. **WIN path ready for Epic 3**
   - `game_ctrl` accepts an `in_goal` input and has a `PLAY -> WIN -> GENERATE` path so Epic 3 can connect goal detection without replacing the controller.
   - With no ball physics in this story, the top-level `in_goal` input is tied inactive; the WIN path is exercised in the controller bench.

5. **Verification**
   - Self-checking controller and top-level integration benches cover startup generation, `gen_done` handoff, manual regeneration, duplicate-button suppression while generating, fresh seeds/different maps, render-read gating, and the WIN path.
   - The existing Stories 1.1-1.3 Vivado regression continues to pass.

## Implementation Tasks

- [x] Add `rtl/game_ctrl.v` with the four architecture states, startup generation, regeneration request handling, `gen_done` handoff, and the Epic 3 WIN hook.
- [x] Adapt the seed capture contract so every non-debug generation receives a fresh stable seed; coordinate changes to the Story 1.3 seed source with its owner.
- [x] Integrate the controller with `top.v`, keeping `BTND` as the temporary regenerate input and preserving the existing maze-size/debug switches.
- [x] Gate maze RAM render reads and video output during generation; coordinate any `maze_ram` or `render` interface changes with their owner.
- [x] Add `tb/tb_game_ctrl.v` and a top-level Story 1.4 integration bench for regeneration, seed progression, render safety, and completed-maze display.
- [x] Add a Vivado runner for the Story 1.4 benches and include the supported regression in the current-stories runner.

## Implementation and Verification Results

- Story 1.4 focused Vivado 2025.2 benches pass: maze generation/seed capture, `game_ctrl`, and top-level regeneration/render-gating integration.
- The current-stories Vivado regression passes, including the existing Story 1.1-1.3 and Story 2.1/2.2 simulation benches.
- Vivado synthesis, implementation, DRC, and bitstream generation complete successfully. Routed timing reports WNS 0.642 ns and WHS 0.071 ns, with no failing setup or hold endpoints. DRC reports zero checks found.
- Generated bitstream: `vivado/labyrinth.runs/impl_1/top.bit` (2,192,127 bytes).
- Vivado reports an existing XDC pin lookup warning for the OLED divider signal, which is not part of the current top-level design. The warning does not prevent bitstream generation.
- Physical Basys 3 testing of this updated top-level design remains pending; verify startup display and BTND regeneration on hardware before marking the story done.

## Pre-requisite Check

- `vga_timing`, `maze_ram`, `render`, `maze_gen`, and `seed_source` are present in `rtl/`.
- Vivado 2025.2 `tb/run_current_stories.tcl` passes the current VGA timing, generated-maze render, maze-generation, and existing input/ROM regression benches.
- The current `top.v` starts generation on reset release and permits `BTND` regeneration, but it has no `game_ctrl` and does not gate the renderer while `maze_gen` writes. Story 1.4 must close this integration gap.
- The current `seed_source` latches only on the first user input. Story 1.4 must provide a fresh seed for every regeneration; otherwise repeated requests can generate the same maze.

## Interface and Design Notes

- Use the single 100 MHz `clk` domain and synchronous active-high `rst` (AD-2).
- Keep the `maze_gen` interface and single-writer rule for `maze_ram` (AD-5).
- `game_state` uses the two-bit values specified in `docs/parallel-workstreams.md`; the renderer consumes completed maze state only.
- `gen_done` marks completion of the final maze write. Do not enable rendering from a partially written map; resume at a frame boundary.
- The existing size control remains `sw[4:1]` (`0` selects 10 cells); fixed-seed debug mode remains `sw[0]`.
- State transition and integration changes should follow `_bmad-output/planning-artifacts/architecture/architecture-2D-Labyrinth-on-FPGA-2026-10-23/ARCHITECTURE-SPINE.md` and `docs/parallel-workstreams.md`.

## Definition of Done

- The controller and top-level regeneration flow satisfy the acceptance criteria.
- The maze renderer cannot read a partially written map, and a completed different maze appears after each non-debug regenerate press.
- Story 1.4 benches and the existing prerequisite regression pass in Vivado 2025.2.
- The Story 1.4 feature branch is reviewed and merged by pull request; request the agreed board integration test for the updated top-level design.
