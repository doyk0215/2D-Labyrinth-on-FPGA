---
story_id: 10.1b
title: Labyrinth Runner menu and state palettes
status: review
owner: CJX
reviewers: [DY, QZ]
depends_on: [10.1a]
---

# Story 10.1b: Labyrinth Runner menu and state palettes

Approved on 2026-11-05 after reviewing native VGA and OLED previews.
Branch `feature/10-1b-menu-ui` builds on pending texture PR #99 (`fc4d5c5`).
The separate OLED footer fix is PR #98 (`a154c7f`).

## Agreed scope

- Title **LABYRINTH RUNNER**, gray stone menu backdrop, dark slate panel and
  teal selection. The four preset difficulties plus CUSTOM make five menu
  choices, matching OLED: EASY, MEDIUM, HARD, EPIC, CUSTOM. No difficulty is added.
- Stage details show the actual maze dimensions and configured per-maze time
  limit. HIGH SCORE replaces the draft MAZE CLEARED wording and reads the
  existing best completed-maze count for that preset, matching OLED HIGH.
  CUSTOM has no stored best record and displays `--`.
- Existing controls stay unchanged. Two symmetric footer columns show
  U/D SELECT / C START and L SETTINGS / R INSTRUCTIONS.
- Beige wall palette is used only in active PLAY. MENU (including settings and
  instructions), PAUSED, WIN and LOSE use gray. Semantic marker/overlay colours
  stay intact. Paused physics, timers and roulette behavior are unchanged.
- No fastest-time feature: CJX withdrew that proposal. Settings/instruction
  layouts and OLED text/icon layouts retain their current functionality.

## Implementation and acceptance

`welcome_menu_overlay` snapshots stage, CUSTOM size and all preset high scores
at the frame boundary. Its font, masks and RGB match the existing one-clock
pixel path. Top-level mode selection is frame-latched; the existing banner
module still draws settings/instructions. Configured timer parameters are
passed to the menu, including custom size limits, so the UI does not hardcode
sample scores or the default countdown values.

Fixed character boxes decode in parallel before the single synchronous font
lookup. The first routed build exposed an overly long origin/divide/string
selection path (WNS -8.715 ns); the revised decoder removes that serial path
while preserving the approved pixels and one-clock overlay alignment.

`render` snapshots the palette with other frame state. `brick_wall_pixel`
retains the approved 16x8 pattern and selects warm/gray RGB444 colours. The
menu also has a charcoal floor/background; ordinary PLAY floor is unchanged.

Acceptance checks:

1. All five menu choices, CUSTOM N=5..20 and preset scores/dimensions/times render
   correctly; selected stage and record agree with OLED data.
2. HIGH SCORE means best consecutive completed mazes for the selected preset,
   not elapsed time or a new scoring mechanism.
3. Buttons retain their existing action, wrap order, configuration and settings.
4. Metadata and palette cannot change midway through a visible frame; gray
   pause returns to warm PLAY without moving the ball or restarting timers.
5. Focused UI/renderer/input regressions and a fresh routed build pass, with
   timing/resource evidence recorded here before the board handoff.

The existing `tb_menu_ctrl` fixture still described the earlier four-stage
menu, 36-bit scores and CUSTOM 2..20. It is updated to the current five-choice,
48-bit score and CUSTOM 5+offset contract; menu-controller RTL is unchanged.

## Validation

Vivado 2025.2 on 2026-11-05:

- `source tb/run_story101b.tcl`: **15/15 PASS**, exit 0, repeated on final RTL
  commit `a264f01` after the timing refactor (20:13 Singapore).
  Includes new welcome/palette checks plus menu controller, legacy banner,
  OLED formatter, generated/top render, rotation, N=15/N=20 cameras, fog,
  WIN/LOSE and existing top menu/settings/replay integration.
- Welcome checks 53,606 text pixels, all preset score slices, CUSTOM bounds,
  dimensions, per-maze time limits, symmetric control hints, blanking and
  live-input snapshot isolation. Palette checks all six shared game states,
  mid-frame stability, pause/resume, menu floor and ordinary PLAY floor.
- Five full 640x480 RTL overlay frames were captured. Geometry/colours match
  the approved preview pixel-for-pixel outside its decorative title shadow;
  the shadow is omitted to keep a single font lookup. The documented preview
  combines that captured overlay with an illustrative gray maze backdrop.
- No full current-stories suite PASS is claimed. The old four-stage fixture
  failures were corrected before the successful final focused run.
- The isolated combined checkout also passes `tb_oled_status_text`, including
  the exact `BTNC MENU` footer from PR #98.

Final combined build completed at 20:19 Singapore. No board PASS is claimed.

- Isolated checkout: `C:/EE2026Projects/labyrinth-combined-ui`, commit
  `c7cce0f43c5333f6f8e9504c9f9737a099367b80`; contains UI RTL `a264f01`,
  texture PR #99 and OLED footer PR #98.
- Fresh project: `C:/EE2026Projects/build-story101b-combined-20261105-201009`.
- Routed timing: WNS **+0.222 ns**, WHS **+0.052 ns**, TNS/THS zero.
  All user-specified timing constraints met; 14,988/14,988 routable nets fully
  routed, zero routing errors. DRC has zero errors (seven existing DSP
  pipelining advisories).
- Placed resources: 8,242 LUTs (39.63%), 7,507 FFs (18.05%), 4.5 BRAM tiles,
  six DSPs, zero MMCM/PLL; within AD-8 budgets.
- Routed clocks include `sys_clk_pin` at 100 MHz and `clk_6m25` at 6.25 MHz;
  zero no-clock pins and zero unconstrained internal endpoints. Existing
  external-I/O delay warnings remain; this does not claim board-interface
  timing signoff. No constraint was weakened for this UI change.
- Stable board file: `C:/EE2026Projects/menu-gray-preview/Story10_1b_Combined.bit`.
  SHA256: `309E319ABBBFC3EC7A39ABE2741D6C2DB0F09B0C3DD97579EE3546D3E94D88BD`.

A fresh fetch after validation still reports `origin/main` at PR #97 merge
`dd55bad`. That exact main revision contains the five-choice controller and
the stale four-choice `tb_menu_ctrl`; updating the fixture is not a new
gameplay feature. Menu controller, game controller, timer and physics RTL
remain unchanged.

## Combined physical-test build

Keep PR #98, #99 and this UI PR separate. Prepare an isolated test checkout
combining this branch and #98; #99 is already its base. Record its exact commit,
bitstream hash and routed timing so one Basys programming session can verify
all three changes without merging them prematurely.

Board checklist:

1. Start/menu: title, gray masonry, HIGH SCORE, five choices, symmetric hints.
   U/D highlights the same stage on VGA and OLED; each preset has its own record.
2. Toggle SW3..SW0 while on CUSTOM: N=5+offset, correct maze/time fields, score
   `--`. EASY/MEDIUM/HARD/EPIC use N=5/10/15/20. SW4 is unused.
3. L settings, U/D rotation rate, C back; R instructions, U/D scroll, C back.
   Both pages retain controls and use gray background walls.
4. C start: warm/beige walls during PLAY. OLED footer reads BTNC MENU (#98).
   Short C returns to menu; long C performs the existing full reset.
5. U pause: gray walls, frozen ball/countdown/effects. OLED U/D selects
   RESUME/RESTART/MENU and C confirms; resume restores warm walls safely.
6. Test smooth rotation and SW15 snap, camera edges on HARD/EPIC, ordinary wall
   collisions, boxes, roulette, invincibility, fog and low-time warning.
7. WIN and TIME UP: gray walls, existing overlays/hold/replay. A successful
   clear increments the run count and updates the selected preset's best score.
8. Record commit, PASS/FAIL and a note/photo. The current v2 workflow in
   docs/parallel-workstreams.md section 7.3 still calls for non-author board
   verification/review before merge; the author's combined test is useful
   integration evidence and does not impersonate that review.
