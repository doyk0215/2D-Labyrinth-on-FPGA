---
story_id: 2.1
story_key: 2-1-read-the-mouse-and-produce-a-rotation-command
title: Read the mouse and produce a rotation command
status: in-progress
owner: QZ
epic: 2
---

# Story 2.1: Read the mouse and produce a rotation command

As the player,
I want my mouse buttons (or the board buttons) turned into a rotation command,
So that I can steer the maze.

## Acceptance Criteria

1. **PS/2 startup and packet decoding**
   - `ps2_mouse` synchronizes PS/2 clock and data through two flip-flops in the 100 MHz domain and uses no derived clock.
   - After reset, it waits for idle lines, performs the host inhibit/request-to-send sequence, transmits `8'hF4` LSB-first with valid odd parity and framing, and accepts the device's low acknowledgement bit.
   - It decodes three-byte stream packets, checking start, odd-parity, and stop bits. Packet alignment begins at a status byte with bit 3 set.
   - Left/right outputs update only after a complete valid packet. `connected` means at least one valid packet has arrived since startup and the packet watchdog has not expired; on timeout it clears the button outputs and retries stream startup.
   - The module exposes only `left_button`, `right_button`, and `connected` to game logic.

2. **Mouse testbench**
   - The self-checking `ps2_mouse` testbench verifies the transmitted `F4` frame, supplies the device acknowledgement, and drives three-byte packets through the receiver.
   - It reports PASS for left-only, right-only, both-button, and no-button packets, and fails if framing or decoded button states are incorrect.

3. **Rotation-command selection**
   - `input_mux` emits signed `rot_cmd`: left-only is `-1`, right-only is `+1`, and both or neither is `0`.
   - While `connected` is asserted, the mouse button states are the selected input source.
   - When no mouse is connected, BTNL and BTNR provide the same command mapping; both or neither also produce `0`.
   - BTNL and BTNR are synchronized into the `clk` domain before reaching `input_mux` (AD-2).

4. **Bring-up indication**
   - The low two LEDs show the signed `rot_cmd` encoding (`2'b11`, `2'b00`, or `2'b01`); remaining LEDs are available to the top-level design.

## Implementation Tasks

- [x] Add `ps2_mouse.v` with PS/2 line synchronizers, host stream-enable transaction, acknowledgement handling, serial receive/parity and stop-bit checks, and three-byte packet assembly.
- [x] Publish only `left_button`, `right_button`, and `connected` from the mouse interface; retain the last complete button state between packets.
- [x] Add `input_mux.v` to choose mouse input when connected and otherwise use BTNL/BTNR, applying the defined both/neither behavior.
- [ ] Coordinate with the top-level owner to synchronize BTNL/BTNR, connect PS/2 pins as open-drain pull-low/release signals, instantiate `ps2_mouse` and `input_mux`, and drive `led[1:0]` from `rot_cmd`.
- [x] Add a self-checking `tb/ps2_mouse_tb.v` for the recorded packet cases and `tb/input_mux_tb.v` for source selection and command mapping.
- [x] Document PS/2 timing constants as parameters and keep all sequential logic on `clk` (no derived clocks).

## Implementation Notes

- The physical PS/2 interface uses `ps2_clk_drive_low` and `ps2_data_drive_low` outputs. The integrating top level must translate these to open-drain pull-low/release behavior and synchronize the board buttons.
- Vivado 2025.2 simulation passes for both `input_mux_tb` and `ps2_mouse_tb`. The reusable command script is `tb/run_story21.tcl`.
- Upstream now includes `rtl/top.v`, and `scripts/create_project.tcl` includes the Story 2.1 modules through its RTL glob. The current top still releases both PS/2 lines, ties LEDs low, and does not instantiate `ps2_mouse` or `input_mux`; the hardware hookup remains for the top-level owner.

## Interface Contract

Use the shared workstream contract and architecture spine:

- Clock and reset: `clk` at 100 MHz and synchronous, active-high `rst`.
- PS/2 clock/data are asynchronous inputs to `ps2_mouse` and must be synchronized before edge detection or sampling. The physical PS/2 lines are open-drain; the top-level boundary pulls low when `*_drive_low` is asserted and otherwise releases the line.
- BTNL and BTNR are asynchronous board inputs and must be synchronized through two flip-flops at the top-level boundary before use by `input_mux`.
- `ps2_mouse` outputs left/right button levels and `connected`.
- `input_mux` inputs mouse buttons, `connected`, BTNL and BTNR; output `rot_cmd[1:0]` as signed `-1`, `0`, or `+1` (`2'b11`, `2'b00`, `2'b01`).
- `rot_cmd` is a level representing the currently held direction, not a pulse. The angle accumulator consumes it in Story 2.2.

## Constraints and References

- Functional requirements: FR5, FR6, FR19.
- Architecture decisions: AD-2 (single clock and input synchronizers), AD-9 (mouse stream mode and board-button fallback).
- Planning source: `_bmad-output/planning-artifacts/epics.md`, Epic 2 Story 2.1.
- Interface source: `docs/parallel-workstreams.md`, section 3, Rotation and Global contracts.
- Hardware context: PS/2 mouse interface via the Basys 3 USB-HID host/PS/2 emulation path; fallback controls are BTNL/BTNR.

## Definition of Done

- Both modules and self-checking testbenches are committed under `rtl/` and `tb/` using plain Verilog-2005.
- The testbenches pass for the specified packet and input-selection cases.
- Top-level integration satisfies the PS/2 open-drain, button-synchronization, and LED indication requirements.
