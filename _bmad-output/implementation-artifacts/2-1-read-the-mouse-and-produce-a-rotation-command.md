---
story_id: 2.1
story_key: 2-1-read-the-mouse-and-produce-a-rotation-command
title: Read the mouse and produce a rotation command
status: review
owner: QZ
epic: 2
---

# Story 2.1: Read the mouse and produce a rotation command

As the player,
I want my mouse buttons (or the board buttons) turned into a rotation command,
So that I can steer the maze.

## Acceptance Criteria

1. **PS/2 startup and packet decoding**
   - `MouseCtl` / `Ps2Interface` run from the 100 MHz system clock and synchronize/debounce the PS/2 lines.
   - On reset, `MouseCtl` resets the mouse, validates the `8'hFA` acknowledgement, `8'hAA` self-test result, and device ID, configures reporting, then enables reports with `8'hF4`.
   - It decodes three-byte stream packets and updates persistent left/right button outputs only after a packet is received.
   - The top-level adapter asserts `mouse_connected` after a packet event and clears it after a 500 ms packet timeout so board-button fallback remains available.

2. **Mouse testbench**
   - `input_mux_tb` verifies left/right command encoding and board-button fallback; `tb_top_story21_integration` verifies fallback LEDs and the PS/2 reset transaction.
   - The existing `ps2_mouse_tb` covers the previous standalone Verilog receiver and is not a test of the active `MouseCtl` path.

3. **Rotation-command selection**
   - `input_mux` emits signed `rot_cmd`: left-only is `-1`, right-only is `+1`, and both or neither is `0`.
   - While `connected` is asserted, the mouse button states are the selected input source.
   - When no mouse is connected, BTNL and BTNR provide the same command mapping; both or neither also produce `0`.
   - BTNL and BTNR are synchronized into the `clk` domain before reaching `input_mux` (AD-2).

4. **Bring-up indication**
   - The low two LEDs show the signed `rot_cmd` encoding (`2'b11`, `2'b00`, or `2'b01`); remaining LEDs are available to the top-level design.

## Implementation Tasks

- [x] Copy the course-supplied `Mouse_Control.vhd` and `Ps2Interface.vhd` into `rtl/` and use them as the active mouse path.
- [x] Adapt the VHDL controller's persistent left/right outputs and `new_event` pulse to the Story 2.1 `mouse_connected` / `input_mux` contract.
- [x] Add `input_mux.v` to choose mouse input when connected and otherwise use BTNL/BTNR, applying the defined both/neither behavior.
- [x] Integrate the top level: synchronize BTNL/BTNR, connect `MouseCtl` to the PS/2 inout pins, instantiate `input_mux`, and drive `led[1:0]` from `rot_cmd`.
- [x] Add a self-checking `tb/ps2_mouse_tb.v` for the recorded packet cases and `tb/input_mux_tb.v` for source selection and command mapping.
- [x] Add `tb/tb_top_story21_integration.v` for board-button fallback, rotation LED encoding, and PS/2 open-drain startup.
- [x] Document PS/2 timing constants as parameters and keep all sequential logic on `clk` (no derived clocks).

## Implementation Notes

- `Ps2Interface` drives the PS/2 inout pins open-drain; the Basys 3 XDC enables pull-ups on C17/B17. Do not add a second PS/2 driver in `top.v`.
- Vivado 2025.2 passes `input_mux_tb` and `tb_top_story21_integration` with the VHDL mouse hierarchy elaborated. The existing `ps2_mouse_tb` remains a regression for the previous standalone Verilog implementation; it does not exercise the active `MouseCtl` path.
- The prior FDP2026 `My_Top_Module` hardware build uses this same VHDL pair and has been confirmed to read the USB mouse. The updated Story 2.1 bitstream was also programmed onto the Basys 3 and physically verified: left click lights LEDs 0 and 1, and right click lights LED 0. The board-button controls and the other stories were also confirmed to work.
- `top.v` synchronizes BTNL/BTNR, instantiates `MouseCtl` and `input_mux`, and derives `mouse_connected` from `new_event` with a 500 ms watchdog. LED[1:0] show `rot_cmd`; LED[3:2] retain maze-generation status.

## Interface Contract

Use the shared workstream contract and architecture spine:

- Clock and reset: `clk` at 100 MHz and synchronous, active-high `rst`.
- PS/2 clock/data are asynchronous to `clk`; `Ps2Interface` synchronizes/debounces them and handles open-drain output. `top.v` passes the board inout pins directly to `MouseCtl`.
- BTNL and BTNR are asynchronous board inputs and must be synchronized through two flip-flops at the top-level boundary before use by `input_mux`.
- `MouseCtl` outputs persistent left/right button levels and a packet `new_event`; `top.v` adapts these to `mouse_connected` for `input_mux`.
- `input_mux` inputs mouse buttons, `connected`, BTNL and BTNR; output `rot_cmd[1:0]` as signed `-1`, `0`, or `+1` (`2'b11`, `2'b00`, `2'b01`).
- `rot_cmd` is a level representing the currently held direction, not a pulse. The angle accumulator consumes it in Story 2.2.

## Constraints and References

- Functional requirements: FR5, FR6, FR19.
- Architecture decisions: AD-2 (single clock and input synchronizers), AD-9 (mouse stream mode and board-button fallback).
- Planning source: `_bmad-output/planning-artifacts/epics.md`, Epic 2 Story 2.1.
- Interface source: `docs/parallel-workstreams.md`, section 3, Rotation and Global contracts.
- Hardware context: PS/2 mouse interface via the Basys 3 USB-HID host/PS/2 emulation path; fallback controls are BTNL/BTNR.

## Definition of Done

- The VHDL mouse sources and Verilog input mux are included in the Vivado project and regression scripts.
- The input-selection and top integration benches pass, and the updated MouseCtl path has passed a physical Basys 3 test with the requested LED mapping.
- Top-level integration satisfies the PS/2 open-drain, button-synchronization, and LED indication requirements.
