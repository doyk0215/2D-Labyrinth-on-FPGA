# Instant time-pickup HUD receipt

The time bonus applies immediately and deliberately leaves any timed buff or
debuff running. The VGA HUD now acknowledges that grant in the existing item
row, using orange RGB444 `f80` text: **TIME +10s** with the default bonus.
After two seconds of PLAY, the row returns to the current timed effect or
ITEM NONE. The panel size and timer row stay unchanged; OLED roulette retains
its existing icon sequence and colours.

The notice uses `item_time_bonus`, the same accepted grant consumed by
`game_timer`. With roulette enabled, it starts on the displayed selected-result
commit, not on box collection or a spinning candidate. It has no output into
gameplay logic. Repeated grants restart its display period, pause freezes the
period, and menu/results/new-maze/reset clear it. Text/colour changes are
captured on VGA frame ticks. Expiry can retain the current picture until the
next frame (up to one frame of display quantization).

The configured bonus amount is used rather than a hardcoded 10: one/two-digit
values use seconds; larger values use MM:SS, matching the timer's 99:59 clamp.
A zero/negative bonus produces no notice. EASY/no-item maps keep their existing
single text row. No scoring, effect durations, timer arithmetic or activation
inputs are changed. This branch starts from main `7659a6e`, which already
contains the OLED footer fix, brick texture and Kim's board-button activation
fix. It is independent of the welcome/menu PR #100.

## Validation

Vivado 2025.2, 2026-11-05: `source tb/run_time_pickup_hud.tcl` **8/8 PASS**.

- Receipt lifetime, pause/resume, repeat grants, frame stability, configured
  large amount, zero amount, reset/new maze/menu, blanking and EASY gating.
- Independent glyph-position model checks all 3,360 pixels in the item row.
- Generated-box pickup with real physics preserves invincibility, adds time
  once, and shows orange `f80` at the real VGA pins. The timed buff is restored
  after the display receipt expires; existing blocked-box respawn still passes.
- Full-top roulette case checks no notice at collection/spin, same-edge grant
  after the selected icon is displayed, orange VGA pixels, exact-once addition,
  and eventual ITEM NONE restoration.
- Existing warning overlay, BCD bonus model, timer countdown, top timeout/reset
  (including Kim's input fix), and roulette state machine pass.

The preview is an actual HUD RTL raster with sample timer inputs (01:52 before,
02:02 after a +10s grant), enlarged 2x with nearest-neighbour pixels:

![Orange time-pickup HUD receipt](time-pickup-hud.png)

Fresh bitstream completed at 21:44 Singapore on 2026-11-05 from RTL commit
`a926d54` (later commits add tests/documentation only):

- Routed WNS **+0.287 ns**, WHS **+0.056 ns**, TNS/THS zero; all user-specified
  timing constraints met. 13,047/13,047 routable nets fully routed, zero errors.
- DRC zero errors; seven existing DSP pipelining advisories remain. Both
  100 MHz and 6.25 MHz clocks are present; no unclocked registers or
  unconstrained internal endpoints. Existing external-I/O delay warnings
  remain; no constraints changed.
- Placed: 6,575 LUTs (31.61%), 7,406 FFs (17.80%), 3.5 BRAM tiles, six DSPs,
  zero MMCM/PLL; within AD-8 budgets.
- Build project: `C:/EE2026Projects/time-pickup-hud/build/sevenseg-vga-status-vivado-20261105-213702`.
- Stable bitstream: `C:/EE2026Projects/time-pickup-preview/TimePickupHUD.bit`.
- SHA256: `FC0E0581D5BA6E44D2F55E2F0F2EE71562D8D90A24BE49A5B5150128481927E0`.

This is main plus the time-pickup fix; unmerged PR #100's menu redesign is not
included in this standalone bitstream. Board test pending; no PASS is claimed.

## Board check

1. Use MEDIUM, HARD, EPIC or a CUSTOM map with item boxes. Collect a buff box
   until roulette selects the time bonus.
2. During the spin the HUD keeps its ordinary item status. At the stopped
   selected result, remaining time increases and the item row reads TIME +10s
   in orange for about two seconds, then restores the ordinary status.
3. Repeat with a timed effect already active. It keeps running underneath the
   notice and reappears with its current remaining duration. A second time
   bonus restarts the notice period without granting twice.
4. Pause during the notice, wait, and resume: the remaining display period is
   preserved. Check menu/restart/timeout clear the notice, normal low-time
   warnings still work, and both mouse and board buttons still start the timer.

Record the source commit and PASS/FAIL with a note/photo before merge review.
