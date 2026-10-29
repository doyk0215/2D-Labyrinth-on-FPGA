---
story_id: 4.4
story_key: 4-4-live-status-and-timer-on-the-oled
title: Live status and timer on the OLED
status: review
owner: QZ
epic: 4
depends_on:
  - 3.3
  - 4.1
  - 4.2
  - 4.3
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/27
---

# Story 4.4: Live status and timer on the OLED

As the player,
I want the stage and elapsed time shown on the OLED while I play,
So that I know how I am doing.

## Story Context

Story 4.1 provides the 4-row by 16-column OLEDrgb text path. Stories 4.2 and
4.3 provide the stage selection, game configuration capture, and settings
pages. Story 3.3 is merged in PR #47 and provides the PLAY/WIN states and
automatic maze replay. These make the live stage and timer display possible.

The top level transfers the 512-bit ASCII `status_text` buffer to the OLED
through a coherent mailbox. The OLED pixel path consumes that text buffer and
does not need access to game state. `game_ctrl` exposes the latched
`active_game_cfg`, `game_state`, and the new-maze `phys_init` pulse. The
configuration currently contains `{rot_speed_sel[1:0], restitution_sel[1:0],
n_cells[3:0]}`; it does not carry a separate stage index. The display must
therefore identify the active stage from the captured stage configuration,
not from the menu's current selection.

This story adds elapsed-time tracking for the active maze and composes a live
status page while preserving the existing menu and settings pages. The timer
freezes on WIN and clears when a new maze begins or reset returns the game to
the menu.

## Acceptance Criteria

1. **Show the active stage and elapsed time**
   - While `game_state` is PLAY, show the stage number for the active maze and
     elapsed time on the OLED; refresh the displayed time at least once per
     second (FR17, FR25).
   - Determine the displayed stage from the latched active configuration so
     it remains correct if the menu selection changes. With the current stage
     table, N=5 maps to stage 1 (EASY) and N=10 maps to stage 2 (HARD).
   - Format the time as minutes and seconds (`MM:SS`). Saturate at `99:59`
     instead of wrapping after the two-digit minute limit.

2. **Define timer start, stop, and clear behavior**
   - Start counting when the generated maze first enters PLAY. Count whole
     elapsed seconds using the board clock, independently of the VGA frame
     rate.
   - Stop advancing the timer when the game enters WIN and retain the final
     elapsed value while the win state is displayed.
   - Clear the timer when a new maze is initialized, including automatic
     replay after WIN. Reset returns the OLED to the existing menu and clears
     the elapsed value.

3. **Preserve menu and configuration behavior**
   - The stage-selection and settings pages continue to work as in Stories
     4.2 and 4.3. Show the live status page only for gameplay and the retained
     final status during WIN; do not change stage or rotation settings.
   - Keep reset-to-menu behavior and game configuration capture unchanged.

4. **Keep the OLED interface isolated and tear-free**
   - The OLED text/pixel driver reads only the coherent `status_text` buffer;
     it must not read `game_state`, the timer, or game configuration directly
     (AD-10).
   - Keep one writer for `status_text`. Pass the required state, active stage,
     and elapsed-time value to the text composer, without adding a second
     driver or bypassing the existing mailbox/frame-snapshot path.
   - Leave `Oled_Display.v`, its clock/reset sequence, and VGA presentation
     unchanged.

5. **Verification**
   - Unit coverage checks one-second timing, counting only in PLAY, freezing
     in WIN, clearing for a new maze/reset, and minute-field overflow behavior.
   - Text-format coverage checks stage mapping from the active configuration,
     elapsed-time formatting, and unchanged menu/settings pages.
   - Top-level coverage checks the complete start-to-PLAY status flow, timer
     stop on the Story 3.3 WIN state, reset-to-menu, automatic replay timer
     clear, and tear-free OLED text updates.
   - Run the focused Story 4.4 benches and current-stories Vivado regression.
     Check synthesis, timing, and resource impact in Vivado 2025.2.
   - Perform the Basys 3 check for stage display, once-per-second timer
     updates, WIN freeze, automatic replay clear, and reset-to-menu behavior.

## Interface and Design Notes

- Use a parameterized system-clock divider for one-second ticks, with a
  default `CLK_HZ` of 100,000,000. Do not derive seconds from `frame_tick`;
  the VGA frame rate is nominally 60 Hz and is not an exact one-second basis.
- Reset or clear elapsed time on reset and `phys_init`, which marks
  initialization of a newly generated maze. Increment only while PLAY and a
  one-second tick are both active. WIN naturally holds the count because the
  timer is not enabled in that state.
- Use `active_game_cfg[3:0]` to distinguish the current stage table entries:
  5 cells is stage 1/EASY and 10 cells is stage 2/HARD. If the stage table
  changes later, update this mapping with the configuration contract.
- Preserve Story 4.2 and 4.3 menu text and Story 4.3's single-writer rule for
  `status_text`. A small formatter or an extended `menu_ctrl` may select the
  display page, but exactly one block owns the final text bus.
- Keep the existing coherent mailbox update and OLED frame snapshot so a
  one-second text change cannot tear the display. The OLED renderer remains
  unaware of game state.
- On automatic replay, the frozen final time is replaced by `00:00` when the
  new maze is initialized and the timer begins counting on entry to PLAY.
- Saturate the BCD timer at `99:59`. This avoids wrapping to a misleading
  short elapsed time during a long play session.

## Implementation Tasks

- [x] Add a parameterized elapsed-time counter with PLAY, WIN, new-maze, and
      reset semantics.
- [x] Add active-stage and elapsed-time formatting to the single-writer OLED
      status-text path; preserve the existing stage/settings screens.
- [x] Add timer-unit, text-format, and top-level OLED integration benches;
      include them in a focused Vivado runner and the current-stories runner.
- [x] Run focused and full Vivado regressions; review timing, resource, and
      DRC results.
- [ ] Perform the Basys 3 status/timer check and record the result in the PR
      and this artifact.

## Prerequisite Check

- Story 3.3 control and visual changes are merged in PR #47 at merge commit
  `56ad662`. The goal-to-WIN-to-new-maze path and `phys_init` handoff are
  available. Its separate Basys 3 check remains pending.
- Story 4.1 OLED text infrastructure and Stories 4.2/4.3 menu, stage, and
  settings code are present on `main` (PRs #40 and #46 merged).
- Story 4.3's board check remains pending; this story uses its merged code
  while retaining the existing menu/settings behavior.
- Source acceptance criteria are in the Story 4.4 section of
  `_bmad-output/planning-artifacts/epics.md` and issue #27.

## Definition of Done

- During PLAY, the OLED shows the active stage and an elapsed timer that
  advances at least once per second.
- The timer freezes on WIN, clears for the next maze and on reset, and reset
  restores the existing menu display.
- The OLED text path remains isolated from game-state signals and updates
  without visible tearing.
- Focused and current-stories Vivado regressions pass, and synthesis/timing/
  resource impact is reviewed.
- The Basys 3 behavior is checked, and the feature is reviewed and merged by
  pull request.

## Implementation Evidence

- `rtl/game_timer.v` divides the 100 MHz system clock into one-second ticks,
  counts in PLAY, freezes in WIN, clears on reset or the new-maze `phys_init`
  pulse, and saturates at 99:59.
- `rtl/oled_status_text.v` formats the active stage and BCD time into the
  existing 4x16 ASCII buffer. MENU text passes through unchanged; PLAY and WIN
  show live/final time, and GENERATE shows a wait page. The top-level keeps
  the coherent `status_text` mailbox and OLED frame-boundary snapshot.
- Vivado 2025.2 focused Story 4.4 tests passed for timer timing/clear/freeze,
  stage/time formatting, and top-level PLAY/WIN/replay/reset and OLED snapshot
  behavior. The current-stories regression also passed, including both OLED
  display modes and the end-to-end top-level ball simulation.
- Routed Vivado 2025.2 check completed without a bitstream. WNS is +0.227 ns
  and WHS is +0.055 ns, with zero failing setup/hold endpoints; all specified
  timing constraints are met. Utilization is 2,911 Slice LUTs (14.00%), 2,576
  Slice Registers (6.19%), 1.5 Block RAM tiles, and 6 DSPs. DRC reports zero
  errors and 11 DSP pipelining advisories. Synthesis completed with zero
  errors and zero critical warnings.
- The Basys 3 live-status and timer check remains pending; no bitstream was
  generated for this Story 4.4 update.
