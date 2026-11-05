# Epic 10: Visual polish and new item outcomes

CJX requested these three stories on 2026-11-05. Implement bounded slices as
separate feature branches and PRs, with simulation/build evidence and a focused
non-author board check. The OLED `BTNC MENU` correction is separate PR #98.

## Story 10.1: Brick walls and clearer screens

As a player, I want stone-brick walls and readable, consistent screens, so the
maze feels coherent and the controls and game state are easy to understand.

Work in small slices because every visual change needs board testing:

| Slice | Scope | State |
| --- | --- | --- |
| 10.1a | Maze wall texture only | Approved preview; this PR |
| 10.1b | Labyrinth Runner welcome/menu and gray non-PLAY palette | Approved; implementation on feature/10-1b-menu-ui |
| 10.1c | Settings/instructions | Planned; layout to agree |
| 10.1d | HUD, pause, results, matching OLED layout where useful | Planned; layout to agree |

10.1a acceptance:

1. Warm stone bricks with staggered 16x8 courses, dark mortar, worn highlights,
   subtle variants and sparse chips match the approved software preview.
2. Texture follows maze coordinates through free/snap rotation and camera
   movement, including fractional camera positions. It never slides in screen space.
3. Only wall colour changes. Floors, markers, boxes, ball, fog, overlays, map
   data, collision geometry, generation, timer and controls retain their behavior.
4. Presets and CUSTOM sizes render correctly, including N=20 far rows/columns
   and map boundaries. Texture/RAM/flags stay aligned without extra pixel latency.
5. Relevant render regressions pass, implementation meets timing/resource limits,
   and a non-author checks a fresh bitstream on the board.

For later slices, agree a preview before editing RTL, preserve navigation and
game behavior, check text clipping/contrast/control accuracy, and test each PR
before widening the visual scope. No new welcome/menu layout is included here.

10.1b uses **HIGH SCORE** for the existing preset best completed-maze count,
matching OLED HIGH; CUSTOM shows `--`. It keeps the approved symmetric hints
and changes walls to gray outside active PLAY (including pause/results), while
PLAY uses beige. See the implementation artifact for the three-PR board checklist.

## Story 10.2: Wall Phaser buff

As a player, I want to cross one interior wall after receiving a buff, so I can
take a shortcut or escape a difficult route.

Confirmed: **one crossing per pickup; the outer border stays solid.** This is
phasing, not permanent wall destruction.

Acceptance:

1. Add a buff-pool result, distinct icon, roulette entry and remaining-charge
   indicator. Activate on the acknowledged stopped-result frame, as current items do.
2. Floor travel consumes nothing. A single passage through an interior wall
   region consumes one charge, without double-counting corners/axis probes.
3. Keep a passage safe until the entire ball clears the wall. Define and test a
   safe exit/recovery transition for cancellation/replacement so the ball cannot
   become embedded in a wall. Ordinary wall collisions resume after the passage.
4. Outer border/out-of-map space always remain solid, and maze bits never change.
5. Pause preserves the charge/passage. New game/regeneration/full reset clear
   it safely. Retain the single-active-effect replacement convention.
6. Cover both axes/directions, corners, map sizes, rotated gravity, charge use,
   replacement, pause/reset and borders in simulation, then build and board-test.

Implementation includes collision handling and item/top integration. The current
roulette uses three-bit icon IDs plus a source bit for eight icons; extend all
icon/source producers, consumers, frame acknowledgements and pools together.
Preserve existing item IDs and frame-atomic OLED updates.

## Story 10.3: Instant Kill debuff (respawn penalty)

As a player, I want a debuff that sends my ball to the start, so red boxes add
risk without ending the current run.

CJX confirmed that “Instant Kill” means **respawn**, not LOSE. Preserve the maze,
remaining time, completed levels and active timed effect; move the ball to its
start and stop its velocity. Invincibility blocks it like other debuffs.

Acceptance:

1. Add a distinct debuff-pool result/icon/roulette entry. Protected pickups use
   the existing invincibility notice and box consumption/respawn behavior.
2. Emit one respawn action on the acknowledged stopped-result frame. A rolling
   or cancelled selection never causes a respawn.
3. At a safe physics/frame boundary, place the ball at its normal start and zero
   both velocities. Discard stale in-flight physics writeback and update camera
   consistently so the next playable frame follows the returned ball.
4. Preserve maze/seed/rotation, item visibility/respawn state, countdown, completed
   levels and current timed effect. Their clocks continue normally; grant no
   time, fresh effect duration or completed level.
5. Stay in PLAY except for an independent terminal event. Do not regenerate or
   show TIME UP because of this item. Define timer-expiry/goal event priorities.
6. Pause freezes pending work; reset/menu/new maze cancels it. Test protected and
   unprotected pickup, exactly-once behavior, state preservation, velocity reset,
   stale writeback and simultaneous events, then build and board-test.

Suggested order: 10.1a and its board check, then agree 10.1b; continue the other
visual slices or schedule 10.2/10.3 according to CJX's next priority. Each item
story gets its own PR; the second reuses the expanded icon/roulette interface.
