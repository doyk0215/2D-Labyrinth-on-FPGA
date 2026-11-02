---
story_id: 9.2
story_key: 9-2-pickup-effect-timer-and-respawn
title: Pickup, effect timer and respawn
status: review
owner: CJX
epic: 9
depends_on: [9.1]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/62
---

# Story 9.2: Pickup, effect timer and respawn

Based on main `8f3b1c3`, after Story 9.1 merged. Includes the requested physical
switch-function swap: **SW0 is snap rotation; SW5 is fixed-seed maze mode**.
No XDC pins change. Fixed seed means the generator reproduces the same map;
it is not a separate hand-written map. The standalone OLED bring-up top keeps
its own unrelated SW0 pattern selector.

## Decisions confirmed by CJX (2026-11-02)

- Keep the full buff/debuff pools and show the selected effect/countdown.
  Only low gravity changes gameplay in this story. Other effects stay timed
  placeholders until Stories 9.3..9.5 implement their consumers/special rules.
- Keep Story 9.1's existing box positions, including possible neighbours of
  start/goal. Revisit placement during Story 9.8 playtesting; no generator
  placement changes are made here.

## Implementation

`item_ctrl` is the only writer of item visibility, active effect, its remaining
seconds and four independent respawn timers. It converts the ball's signed
Q9.8 centre to a bounded active-map tile and checks the generated positions
on `phys_done`. This uses the committed physics position in vertical blanking.
Contact with the ball radius alone does not pick up a box.

A pickup publishes a one-clock event, hides one box, starts a fresh default
8-second timer and replaces the active timed placeholder. Slot 0/1 chooses
from IDs 0..2; slot 2/3 from 3..7, matching the icon ROM. Rejection-sampled
candidates are cached from a nonzero xorshift32 RNG, so the pickup path has no
modulo/divider. Identical seed and input timing reproduce identical rolls;
new pickups sample a fresh RNG progression and may legitimately repeat a code.

Each box has its own default 15-second clock counter. When ready it waits
until the ball has left, and appears at the next physics completion. Visibility
never changes just because a second expires during an active VGA scan. WIN or
LOSE clears active effect and respawn timers while retaining the frozen box
picture. MENU/GENERATE/reset clear visibility; `phys_init` reloads valid boxes.
Duration is clamped to the OLED's two-digit 0..99 s range; wide constant math
sizes respawn counters without 32-bit multiply overflow.

The top connects visibility to render, effect code to physics and effect/seconds
to OLED. Low gravity halves the entire signed gravity product before the
integer/fraction split, keeping fractional carry in its existing units. The
effect selection is captured with per-frame trig, so a mid-pipeline expiry
cannot mix normal and low gravity. Speed cap, collisions and restitution do
not change; no new DSP is used by this operation.

The OLED PLAY row is exactly 16 ASCII characters: `ITEM:LOW GRAV 08` (no space
after the colon). Names are shortened to fit. No active effect restores
PLAYING; WIN/TIME UP/menu pages keep their own text and frame-safe mailbox.

`ITEM_STUB_LOW_ONLY` exists only as a parameterized test/demo hook, default
false. The shipping default uses full pools. The top integration bench sets
it false in the final shipping-configuration integration test, exercising
both buff and debuff code wiring with full pools. An initial integration run
also passed with the low-only hook, and the controller bench covers that hook
and all eight default pool members. No physical switch uses this hook.

## Handoff contracts

- `ITEM_EFFECT_W=4`, codes 0..7 match `item_icon_rom`; NONE=15. DY/QZ must
  approve the shared header/consumer interface changes.
- 9.3: consume gravity codes beyond LOW_GRAV in `ball_physics.effect_code`.
- 9.4: consume INVERT/FOG in controls/render. These codes do not act yet.
- 9.5: implement invincibility's debuff blocking and instant time bonus that
  adds time without replacing the current timed effect. The 9.2 placeholder
  timer/selection deliberately does not claim either gameplay behavior.
- 9.7: add roulette busy/pickup blocking and delayed effect activation, using
  pickup event/index/code as the hook. 9.2 activates immediately.

## Simulation

```tcl
set repo [pwd]
source [file join $repo tb run_story92.tcl]
source [file join $repo tb run_current_stories.tcl]
```

- `tb_item_ctrl`: full pool membership/all eight codes, exact effect seconds,
  replacement/restart, independent box cooldowns, occupied respawn, visibility
  only at physics completion, fresh rolls, seed determinism, signed half-open
  tile boundaries, N=15 and out-of-map aliases, state/reset clearing. Also
  checks the optional low-only hook separately from the default full pools.
- `tb_item_gravity`: independent integer-product model over all octants,
  including negative gravity, normal/low transitions and a changed code after
  its snapshot. Low gravity against border walls/corners at all restitution
  settings retains the 5 px/frame cap and never crosses walls.
- `tb_switch_mapping`: all four SW0/SW5 combinations, real fixed/free-running
  seed behavior and actual smooth/snap angle changes. Existing top-level
  fixtures move their former fixed-seed bit from SW0 to SW5, while the OLED
  bring-up fixture remains unchanged.
- `tb_top_story92_items`: real generated positions/RAM, actual physics-done
  pickup, box colour before/after consumption, reappearance on departure,
  full-pool effect-bus wiring, full OLED frame snapshot, both box types and
  reset/WIN/LOSE clearing. Only ball placement and shortened timing are used
  to make this coverage independent of a player's steering.
- Existing formatter fixture checks complete item rows, decimal seconds,
  expiration/no-effect fallback and WIN/LOSE priority. Legacy physics benches
  explicitly tie the new effect input to NONE to preserve their old scenarios.

## Validation

Focused five-bench suite PASS on 2026-11-02. Full regression and routed build
results are added after completion. Hardware verification is pending.

## Non-author board checklist

QZ/DY must review their physics/top/renderer/OLED interfaces and the shared
header. Someone other than CJX records board PASS/FAIL, tested commit and a
photo/note on the PR, per `docs/parallel-workstreams.md` section 7.3.

1. Program the new 9.2 bitstream. Check SW0=0 gives smooth rotation and SW0=1
   gives 90-degree press/release snap. Independently toggle SW5: 1 repeats a
   fixed-seed map on regeneration, 0 gives fresh maps.
2. Pick up buff/debuff boxes on EASY/HARD/HUGE. Each disappears and the OLED
   shows its selected pool item and about eight seconds remaining. LOW GRAV
   reduces acceleration; all other codes are placeholders until 9.3..9.5.
3. A new pickup replaces/restarts the timed placeholder. After about 15 s a
   consumed box returns at the same location. If the ball is still there,
   it remains hidden until the ball leaves; returning picks it up again.
4. Recheck collisions/speed cap while low gravity starts/ends. Win, timeout,
   short/full reset and replay clear item state appropriately. No map tearing
   or mixed OLED text should appear.
5. During 9.8 decide whether near-start/goal boxes need exclusion, and tune
   effect/respawn durations. Placement is unchanged in this PR.
