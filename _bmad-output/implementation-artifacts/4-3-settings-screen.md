---
story_id: 4.3
story_key: 4-3-settings-screen
title: Settings screen
status: review
owner: QZ
epic: 4
depends_on:
  - 4.2
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/26
---

# Story 4.3: Settings screen

As the player,
I want to adjust rotation speed and optionally restitution,
So that the game feels the way I like.

## Story Context

Story 4.2 is complete: PR #40 is merged and issue #25 is closed. Stories 1.4
and 4.1 are also complete. The top level already has the 4-row by 16-column
OLED text path, `menu_ctrl`, synchronized board-button paths, and an 8-bit
`game_cfg` bus. Its layout is
`{rot_speed_sel[1:0], restitution_sel[1:0], n_cells[3:0]}`. The stage menu
currently keeps `rot_speed_sel` at zero, while `angle_accumulator` runs at a
fixed nominal 90 degrees per second.

This story adds a settings page to the existing menu and makes the selected
rotation rate part of the game configuration. Restitution remains controlled
by the Story 4.2 stage table; editing restitution is optional in FR24 and is
out of scope here.

## Acceptance Criteria

1. **Reach and leave settings**
   - In `MENU`, a debounced BTNL press opens the OLED settings page from the
     stage-selection page. BTNU/BTND change the selected setting; BTNC returns
     to stage selection without starting a game. BTNC on the stage-selection
     page retains its Story 4.2 behavior and starts the selected stage.
   - Returning from settings preserves both the selected stage and the chosen
     rotation rate. Reset returns to stage selection; the selected rate
     persists until power-on reset.
   - Menu button actions do not rotate the maze. In `PLAY`, BTNL/BTNR and the
     mouse keep their existing rotation behavior.

2. **Rotation-rate choices and configuration**
   - Provide four documented presets using the existing `rot_speed_sel[1:0]`:

     | Code | Label | Nominal rate |
     | --- | --- | ---: |
     | `00` | NORMAL (default) | 90 degrees/s |
     | `01` | SLOW | 45 degrees/s |
     | `10` | FAST | 135 degrees/s |
     | `11` | TURBO | 180 degrees/s |

   - Keep the current default behavior at code `00`. Display the selected
     label on the OLED and place the selected code in `game_cfg[7:6]` while
     preserving the stage's `restitution_sel[5:4]` and `n_cells[3:0]`.
   - Rotation rate affects smooth rotation only. Story 2.4's 90-degree snap
     gesture remains one quadrant per completed press at every preset.

3. **Apply settings to the next game**
   - `game_ctrl` captures the selected configuration at the existing
     frame-safe game-start handoff. `angle_accumulator` uses the captured
     `active_game_cfg[7:6]`; editing the menu value cannot change an active
     game's rotation rate.
   - The rotation setting changes only the angle increment. It does not change
     gravity, the 5 px/frame per-axis physics cap, or wall restitution.

4. **Timing and OLED integration**
   - Settings text uses the existing coherent OLED frame snapshot and does not
     tear when the selection changes. The OLED driver and its clock/reset
     sequence remain unchanged; VGA output remains free of menu content.
   - Settings-page input is synchronized and debounced. Existing play-mode
     rotation controls remain unchanged.

5. **Verification**
   - A `menu_ctrl` bench covers page entry/exit, all four rates, display text,
     stage retention, reset behavior, and the distinction between return and
     start actions.
   - An `angle_accumulator` bench checks the signed rotation direction and
     exact nominal angle delta for every rate over 60 frame ticks. The
     implementation uses fractional carry so rates not divisible by 60 do
     not accumulate long-term rounding error.
   - A top-level Story 4.3 bench verifies synchronized/debounced navigation,
     selected rate reaching `game_cfg`, latching into `active_game_cfg`, no
     mid-game rate change, unchanged snap behavior, and tear-free OLED text.
   - The Story 4.3 bench and existing current-stories regression pass in
     Vivado 2025.2.

## Interface and Design Notes

- Keep `menu_ctrl` as the only writer of `game_cfg` and `status_text` (AD-5).
- The four settings map to nominal angle increments of 512, 1024, 1536, and
  2048 angle counts per second. At the existing nominal 60 Hz frame basis,
  use whole-step plus remainder values `(8,32)`, `(17,4)`, `(25,36)`, and
  `(34,8)` respectively. The existing 90-degree/s preset therefore remains
  bit-for-bit compatible. The actual 59.52 Hz VGA frame rate scales the
  observed rates by the same factor as before.
- Use the currently synchronized BTNL input for a settings-page press event;
  add or reuse a menu-only debounce path. Gate rotation commands while the
  game is in `MENU`, so entering settings cannot change the hidden maze angle.
- Reset handling must distinguish power-on reset from the BTNC return-to-menu
  pulse: reset the preset to NORMAL only on power-on, while retaining it across
  a game reset. The stage selection still returns to its initial stage as in
  Story 4.2.
- When `active_game_cfg` is latched, use its speed bits for the full game.
  Settings editing remains a menu action; a setting selected after a game
  starts is used by the next game.
- Keep stage-specific restitution fixed as defined by Story 4.2. Do not add
  a restitution editor, change the 5 px/frame physics cap, add pins, or modify
  the course-supplied `Oled_Display.v`.

## Implementation Tasks

- [x] Extend `menu_ctrl` with a settings page and a persistent rotation-rate
      selection; keep stage navigation and confirmation unchanged.
- [x] Add the menu-only BTNL press handling and gate smooth/snap rotation in
      `MENU` while preserving BTNL/BTNR and mouse controls in `PLAY`.
- [x] Pass `active_game_cfg[7:6]` into `angle_accumulator` and implement the
      four fractional-carry rate presets.
- [x] Add `tb_menu_ctrl` settings coverage, extend `tb_angle_accumulator`, and
      add a top-level Story 4.3 integration bench plus Vivado runner.
- [x] Run the Story 4.3 benches and current-stories Vivado regression; check
      synthesis, timing, and resource impact in Vivado 2025.2.
- [ ] Perform the settings navigation and rotation-rate board check; record
      the result in the PR and this artifact.

## Prerequisite Check

- Story 1.4: tracker marks it done; PR #37 is merged and issue #15 is closed.
- Story 4.1: tracker marks it done; PR #9 is merged and issue #24 is closed.
- Story 4.2: PR #40 merged on 2026-10-27 and issue #25 closed. Its stage menu,
  game configuration capture, and OLED text path are available on `main`.
- Story 4.3 source: issue #26 is open and lists Story 4.2 as its prerequisite.

## Definition of Done

- The player can open the OLED settings page, select a rotation preset, return
  to stage selection, and start without losing the selected stage or speed.
- The selected rate takes effect on the next game's smooth rotation, and the
  current active configuration remains stable for the duration of a game.
- Unit, top-level, OLED, and current-stories Vivado regressions pass; resource
  and timing impact are reviewed; the board behavior is checked.
- The feature is reviewed and merged by pull request.

## Implementation Evidence

Implemented on `feature/4-3-settings-screen`.

- Vivado 2025.2 Story 4.3 runner and current-stories regression passed,
  including both OLED modes. The integration bench verified settings-page
  navigation, coherent OLED text snapshots, the FAST selection captured for
  the next game, stability of the active game's rate, and the measured 1536
  angle-count delta over 60 frame ticks.
- Routed the Basys 3 `My_Top_Module` design in an isolated temporary Vivado
  project. Timing summary: WNS 0.551 ns, WHS 0.073 ns, zero failing setup or
  hold endpoints; all user-specified constraints are met. Utilization: 2703
  Slice LUTs (13.00%), 2309 Slice Registers (5.55%), 1.5 Block RAM tiles, and
  6 DSPs. DRC reported zero errors and nine DSP pipelining advisories.
- No bitstream was generated. Physical settings navigation and rotation-rate
  behavior remain pending a teammate's Basys 3 test.
