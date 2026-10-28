---
story_id: 4.2
story_key: 4-2-choose-a-stage-and-start-the-game-on-the-oled
title: Choose a stage and start the game on the OLED
status: done
owner: QZ
epic: 4
depends_on:
  - 1.4
  - 4.1
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/25
---

# Story 4.2: Choose a stage and start the game on the OLED

As the player,
I want to choose a stage on the OLED and start playing,
So that I control the difficulty.

## Story Context

Stories 1.4 and 4.1 are merged. The game controller, maze generator, renderer,
and reusable OLEDrgb text path are present. Story 4.1 was verified using the
stand-alone `oled_rgb_bringup_top`. At Story 4.2 kickoff, `My_Top_Module.v` held the OLED
pins idle; this implementation now connects the menu and OLED path to the game
top and gates game start on stage confirmation.

## Acceptance Criteria

1. **Menu at startup and reset**
   - After power-on reset, `game_ctrl` enters `MENU`; no maze generation starts
     until the player confirms a stage.
   - The OLED shows a stage-selection menu. The VGA monitor shows no menu
     content; keep the background visible until the completed maze enters
     `PLAY`.
   - Reset from outside `MENU` returns the controller and menu to their initial
     selection in `MENU`.

2. **Stage navigation**
   - Synchronized, debounced `BTNU` and `BTND` presses move the selection up
     and down, one stage per press. Navigation changes the highlighted stage
     on the OLED and does not start generation.
   - Provide at least two selectable stages. Each stage has a documented
     `n_cells` value and 2-bit `restitution_sel`; include a stage with
     `n_cells < 10` and keep all values within the maze generator's supported
     range.

3. **Confirm and start**
   - A debounced `BTNC` press while in `MENU` confirms the selected stage.
   - `menu_ctrl` owns and presents the selected `game_cfg` fields:
     `n_cells[3:0]`, `restitution_sel[1:0]`, and the default
     `rot_speed_sel[1:0]` reserved for Story 4.3.
   - The selected configuration remains stable through game start. The game
     controller accepts the confirmation and enters `GENERATE` on a frame
     boundary; the maze generator receives the selected `n_cells`.
   - A short `start_game` pulse must not be lost while waiting for
     `frame_tick`; latch the request or hold it until accepted.

4. **Maze and display integration**
   - The selected smaller maze is generated and rendered centred in the
     existing tile map, with no out-of-range map accesses.
   - Rendering stays disabled while the controller is in `MENU` or
     `GENERATE`; only the completed maze is shown in `PLAY`.
   - Reuse the Story 4.1 `Oled_Display.v` unmodified, `oled_clk_div`,
     `oled_text_pixel`, and `font_rom`. Show the menu through the existing
     4-row × 16-column text buffer on the 96 × 64 OLEDrgb.

5. **Reset/confirm input behavior**
   - The current top uses `BTNC` as a raw global reset, while this story also
     uses `BTNC` to confirm. Replace that conflict with an internal power-on
     reset and state-dependent `BTNC` handling: in `MENU`, it confirms; outside
     `MENU`, it returns the game to `MENU`. Keep the behavior synchronized,
     debounced, and covered by tests.

6. **Verification**
   - A self-checking `menu_ctrl` bench covers stage navigation, displayed
     selection, configuration values, confirmation, and reset-to-menu.
   - A top-level integration bench proves no generation before confirmation,
     frame-safe handoff to `GENERATE`, selected maze size, VGA menu isolation,
     and OLED menu text output.
   - The OLED regression and the existing current-stories Vivado regression
     continue to pass.

## Interface and Design Notes

- Keep `menu_ctrl` as the sole writer of `game_cfg` and `status_text` (AD-5).
- Use the game-configuration fields already specified in
  `docs/parallel-workstreams.md`. Define and document the packed bus layout or
  use explicit named ports; do not add unrelated settings behavior from Story
  4.3.
- The epic does not prescribe stage labels or exact restitution codes. Define
  a small stage table in `menu_ctrl`, document its `N` and restitution mapping,
  and keep the mapping in one place for the bench and display.
- `Oled_Display` needs its existing 6.25 MHz clock and reset sequence. Keep
  menu logic on the 100 MHz system clock, and transfer text to the OLED clock
  domain as a coherent frame snapshot so a menu update cannot tear a frame.
- Use the current 4.1 pin mapping: `Oled_Display.vccen` to `oled_vbatc` and
  `Oled_Display.pmoden` to `oled_vddc`, as in `oled_rgb_bringup_top`.
- `game_ctrl` currently changes `MENU` to `GENERATE` only when `start_game`
  coincides with `frame_tick`. Its request handling must support a debounced
  button pulse at any point in the frame.
- `My_Top_Module.v` is owned by CJX. Coordinate the top-level OLED and button integration
  with that owner; request DY's board check as required by `docs/work-order.md`.

## Implementation Tasks

- [x] Add `rtl/menu_ctrl.v` with MENU navigation, a documented stage table,
      stable `game_cfg`, and the 4 × 16 `status_text` buffer.
- [x] Add synchronized/debounced menu button handling. Resolve `BTNC` confirm
      versus reset using the state-dependent behavior above and an internal
      power-on reset.
- [x] Extend the game-control start/config interface so a one-cycle confirm
      request is held until the next frame boundary and the chosen configuration
      is captured for the game.
- [x] Connect the menu configuration to maze generation; replace the temporary
      switch-based maze size with the selected `game_cfg.n_cells` while
      preserving the debug-seed switch.
- [x] Integrate the existing OLEDrgb clock divider, text rasterizer, and
      unmodified display driver into `My_Top_Module.v`; transfer menu text coherently into
      the OLED clock domain.
- [x] Keep VGA output free of menu pixels and keep maze render reads disabled
      until generation is complete and the controller reaches `PLAY`.
- [x] Add `tb/tb_menu_ctrl.v`, a top-level Story 4.2 integration bench, and a
      Story 4.2 Vivado runner; include the supported regression coverage.
- [x] Run the current-stories regression and build the Basys 3 bitstream.
- [x] Recheck the OLED/menu hardware after moving the Pmod OLED from JA to JB.

## Prerequisite Check

- Story 1.4: PR #37 is merged; issue #15 is closed. `game_ctrl` and top-level
  generation/render gating are present.
- Story 4.1: PR #9 is merged; issue #24 is closed. The OLEDrgb driver, clock
  divider, text rasterizer, font, and OLED testbench are present and the PR
  records simulation and Basys 3 checks.
- Before Story 4.2 implementation, the game top tied the OLED pins idle and did
  not instantiate `menu_ctrl` or `Oled_Display`; that hookup is now implemented.
- Before Story 4.2 implementation, the controller defaulted to `GENERATE` and
  did not queue `start_game` across frame boundaries. The game top now selects
  MENU startup and `game_ctrl` queues both the request and its configuration.

## Definition of Done

- The player sees and navigates the stage menu on the OLED; the game does not
  generate or show a maze until confirmation.
- Confirmation transfers the documented stage configuration and starts the
  selected maze at the next frame-safe handoff. Reset returns to the menu.
- Unit, integration, OLED, and current-stories Vivado regressions pass; the
  updated Basys 3 bitstream and menu behavior are checked on hardware.
- The feature branch is reviewed and merged by pull request.

## Implementation Evidence

- Vivado 2025.2: current-stories regression passed, including Story 4.2 menu
  unit and top-level integration coverage. Story 4.1 OLED colour-pattern and
  text-frame simulations both pass.
- Basys 3 bitstream generated at
  `vivado/labyrinth.runs/impl_1/My_Top_Module.bit`. The post-rename routed timing
  report shows zero failing setup and hold endpoints (worst setup slack
  0.183 ns; worst hold slack 0.074 ns).
- Physical Basys 3 OLED/menu behavior passed with the Pmod OLED on header JB,
  as reported by QZ on 2026-10-26. PR #40 merged on 2026-10-27 and issue #25
  closed, completing the story.
- After renaming the HDL module to `My_Top_Module`, Vivado 2025.2 current-stories
  regression and both OLED display modes passed on 2026-10-27. Synthesis,
  implementation, DRC, and bitstream generation also completed with zero errors.
