---
title: 'Wall breaker buff item'
type: 'feature'
created: '2026-11-05'
status: 'in-review'
baseline_commit: '654fbf22c880c75f750c804fbf4b422ffefa7b52'
route: 'dispatch'
review_loop_iteration: 0
context: ['{project-root}/docs/epic10-enhancements.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Item boxes can only change gravity, protection, time, controls and visibility. DY wants a buff that changes the maze itself.

**Approach:** Add a fourth buff, WALL BREAKER. When the item roulette selects it, a bomb removes the interior wall tiles in a 5 x 5 block (blast radius 2) centred on the ball's tile. The removed walls stay open until the maze is next generated.

## Boundaries & Constraints

**Always:**
- The effect is instant: no timer, no HUD countdown, no `active_effect`. It must not end or refresh an effect that is running (same rule as TIME BONUS).
- Only interior tiles change (tile col/row 1 .. 2N-1). The outer border (0 and 2N) and everything outside the map stay solid. Only wall tiles become floor, so start, goal, boxes and floor are unchanged.
- The map is edited only at a physics-completion (`phys_done`) in PLAY, in vertical blanking, so a frame is never drawn half-edited and physics never reads mid-edit. A request made earlier waits for the next `phys_done`. PAUSED keeps it waiting; leaving PLAY, `phys_init` or reset discards it.
- `maze_gen` stays the only writer outside a blast and always wins the write port. Generation clears all 4096 tiles, so a new or regenerated maze (BTND, replay, next level) is intact again.
- Existing item ids, icon ids 0..7, pool sizes for debuffs and the pickup, respawn, block and commit timing are unchanged. The breaker is a buff, so Invincible never blocks it.
- Radius is one parameter (`BLAST_RADIUS`, default 2) so it can be tuned in a playtest.

**Never:** Wall Phaser (Story 10.2), permanent maze edits, edits to `maze_gen`, the generator seed or collision code, a new HUD row, or any change to the 3 known-failing benches (`tb_top_story44_integration`, `tb_top_story83_time_up`, `tb_top_story97_roulette`).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Centre cell | ball on a cell centre, N=10, breaker commits | all 25 tiles in the 5x5 block that are interior walls become floor | N/A |
| Near border | ball at tile (1,1) | tiles with col/row 0 stay wall; the rest of the block clears | border never written |
| Far corner N=20 | ball at tile (39,39) | col/row 40 stay wall; tiles 37..39 clear | 6-bit coords, no alias onto 0..8 |
| Paused when committed | commit, then PAUSED | nothing written until PLAY and the next `phys_done` | pending kept |
| Regenerate | BTND, WIN replay, new level | generation rewrites the map; broken walls are gone | pending cleared by `phys_init` |
| Active effect | invincible running, breaker commits | effect and its seconds are unchanged | N/A |
| Roulette | buff box picked up | breaker is one of 4 buff results; spin shows icons 0,1,2,8 | N/A |

</frozen-after-approval>

## Code Map

- `rtl/labyrinth_pkg.vh` -- add `ITEM_WALL_BREAKER 4'd8`.
- `rtl/item_ctrl.v` -- buff roll becomes 2-bit uniform (3 maps to code 8); breaker is not a timed effect: skip the `active_effect` update on both commit and immediate paths; new `wall_breaker_pulse` (deferred: `commit_now && pending_effect==8`, immediate: `pickup_now && rolled_effect==8`).
- `rtl/item_roulette.v` -- icon/chosen 4 bits, `visual` 5 bits (`[4]` = showing, `[3:0]` = icon); accept pickup_effect 8 as a buff; buff spin order 0,1,2,8.
- `rtl/item_icon_rom.v`, `scripts/make_item_icons.ps1`, `tb/data/item_icons*.mem`, `docs/v2-item-icons.png` -- 9th icon (green frame buff), 4-bit icon input, 6-bit palette index. The ROM file is generated, so change the script and regenerate.
- `rtl/oled_roulette_pixel.v` -- 4-bit icon input.
- `rtl/wall_breaker.v` (new) -- pending flag, tile centre from ball position (same arithmetic as `item_ctrl`), 25-step clear on `phys_done`; drives `we/waddr/wdata=0`.
- `rtl/My_Top_Module.v` -- widen the visual mailbox/pending/active regs to 5 bits (lines ~306-308, 961-1040); instantiate `wall_breaker`; mux the `maze_ram` write port (generator has priority).
- `rtl/maze_ram.v`, `rtl/maze_gen.v`, `rtl/ball_physics.v`, `rtl/render.v` -- no change. Reads are continuous, so edits are seen on the next read.
- Benches to update for the wider bus and new roll: `tb_item_roulette`, `tb_oled_roulette_pixel`, `tb_item_icon_rom`, `tb_item_ctrl`, `tb_story95_items`, `tb_top_story97_roulette`, `tb_top_story95_buffs`, `tb_top_story92_items` as needed; new `tb_wall_breaker` and a top-level wiring check.

## Tasks & Acceptance

**Execution:**
- [x] `rtl/labyrinth_pkg.vh` -- add the item code.
- [x] `rtl/item_ctrl.v` -- new roll, pulse, no `active_effect` change for code 8.
- [x] `rtl/item_roulette.v`, `rtl/oled_roulette_pixel.v`, `rtl/My_Top_Module.v` -- 5-bit visual bus and 4-bit icon.
- [x] `scripts/make_item_icons.ps1` -- add the icon, regenerate ROM, mem files and preview.
- [x] `rtl/wall_breaker.v` + top write-port mux.
- [x] Benches: `tb_wall_breaker` (matrix rows), update the affected existing benches, add a top-level check that a roulette-selected breaker opens walls in `maze_ram_i.tile_mem`.

**Acceptance Criteria:**
- Given a breaker commit in PLAY, when the next `phys_done` arrives, then all interior wall tiles within radius 2 of the ball tile read 0 and every other tile is unchanged.
- Given any state, when no breaker was committed, then the map and all existing bench results are as before.
- Given the routed build, then WNS >= 0 and WHS >= 0 and resources stay within AD-8.

## Verification

**Commands:**
- `vivado -mode batch -source C:/t1/one.tcl -tclargs C:/wb C:/t1/rwb <benches>` -- expected: every listed bench PASS
- `vivado -mode batch -source scripts/build_bitstream.tcl` from `C:\wb` with `TEMP=C:\t1\tmp` -- expected: bitstream written, WNS and WHS >= 0

### Implementation notes (2026-11-05)

- Decisions confirmed by DY: 5 x 5 blast (radius 2), flat 1-in-4 roll among the four buffs, no on-screen message beyond the roulette icon and the blast itself.
- `item_ctrl` buff roll is now `buff_roll<=rng[1:0]` every clock (the old rejection sampling is gone, because all four values are valid); 3 maps to `ITEM_WALL_BREAKER`. Benches that wait for a roll and then pick up now `force` the roll (`tb_item_ctrl`, `tb_story95_items`) because it changes every clock.
- Visual bus is 5 bits (`[4]` = showing, `[3:0]` = icon); the icon ROM has 9 icons and a 36-entry palette, regenerated by `scripts/make_item_icons.ps1`.
- `wall_breaker` fires on the first `phys_done` after the roulette grant (or the same clock). The map write port is shared: `maze_gen` wins (`maze_we = gen_we | brk_we`).
- New benches: `tb_wall_breaker` (unit, all matrix rows), `tb_top_wall_breaker` (real pickup, 5x5 edit in `maze_ram`, running effect untouched, BTND restores the map). Both are registered in `tb/run_current_stories.tcl`.
- Full regression: 49 PASS; 8 not passing and none caused by this change: `tb_top_story44_integration`, `tb_top_story83_time_up`, `tb_top_story97_roulette` (OLED mailbox, fail on main), `tb_top_story73_camera`, `tb_top_story74_stage`, `tb_top_story14_integration`, `tb_top_ball` (stale after CUSTOM = 5 + offset, fail on main) and `tb_top_story92_items` (watchdog in the full run, PASS alone).
- Routed build (before merging PR #101): WNS +0.253 ns, WHS +0.084 ns, 8,351 LUTs, 7,546 FFs, 4 BRAM tiles (4.5 before: the map RAM mapping changed with the shared write port).
