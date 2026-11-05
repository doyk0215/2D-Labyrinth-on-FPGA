---
story_id: 10.1b
title: Labyrinth Runner menu and state palettes
status: in-progress
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
  teal selection. All five stage choices appear on VGA and use the existing
  OLED/menu selection: EASY, MEDIUM, HARD, EPIC, CUSTOM.
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

`render` snapshots the palette with other frame state. `brick_wall_pixel`
retains the approved 16x8 pattern and selects warm/gray RGB444 colours. The
menu also has a charcoal floor/background; ordinary PLAY floor is unchanged.

Acceptance checks:

1. All five stages, CUSTOM N=5..20 and preset scores/dimensions/times render
   correctly; selected stage and record agree with OLED data.
2. HIGH SCORE means best consecutive completed mazes for the selected preset,
   not elapsed time or a new scoring mechanism.
3. Buttons retain their existing action, wrap order, configuration and settings.
4. Metadata and palette cannot change midway through a visible frame; gray
   pause returns to warm PLAY without moving the ball or restarting timers.
5. Focused UI/renderer/input regressions and a fresh routed build pass, with
   timing/resource evidence recorded here before the board handoff.

The existing `tb_menu_ctrl` fixture still described the earlier four-stage
menu, 36-bit scores and CUSTOM 2..20. It is updated to the current five-stage,
48-bit score and CUSTOM 5+offset contract; menu-controller RTL is unchanged.

## Validation

Menu text/snapshot checks and state-palette checks pass. Broader regression and
build results will be appended after completion. No board PASS is claimed.

## Combined physical-test build

Keep PR #98, #99 and this UI PR separate. Prepare an isolated test checkout
combining this branch and #98; #99 is already its base. Record its exact commit,
bitstream hash and routed timing so one Basys programming session can verify
all three changes without merging them prematurely.

Board checklist:

1. Start/menu: title, gray masonry, HIGH SCORE, five stages, symmetric hints.
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
