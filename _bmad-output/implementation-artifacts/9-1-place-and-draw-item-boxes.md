---
story_id: 9.1
story_key: 9-1-place-and-draw-item-boxes
title: Place and draw item boxes
status: review
owner: DY
epic: 9
depends_on: [7.5]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/61
---

# Story 9.1: Place and draw item boxes

Each maze now has two buff boxes and two debuff boxes, one in each quadrant,
drawn on the monitor. Nothing picks them up yet (Story 9.2). Spec:
[spec-9-1-place-and-draw-item-boxes.md](spec-9-1-place-and-draw-item-boxes.md).

DY wrote all of 9.1, including the `maze_gen` placement that
`docs/parallel-workstreams.md` gave to QZ (decided by DY on 2026-11-02); QZ
reviews it.

## Implementation

- `maze_gen` places the boxes last, after the maze and its loops, so every
  map is unchanged. The cell grid is split at h = N/2 into four quadrants
  (0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left). Box k goes in
  quadrant (r + p_k) mod 4, where r and a swap bit come from the RNG and
  p = 0,1,2,3 or 0,2,1,3, so any of the six quadrant pairs can hold the
  buffs: each side-by-side pair 1 time in 8, each diagonal pair 1 time in 4.
  Inside its quadrant a cell is drawn by rejection sampling, never the start
  or goal cell. Boxes 0 and 1 are buff boxes, 2 and 3 debuff boxes.
- New outputs `box_cols`, `box_rows` (box k at bits 5k+4:5k, tile
  coordinates) and `box_valid`. All three clear on reset and when a
  generation starts. N = 2 and 3 (legacy switches only) get no boxes.
- `render` draws a box on a box tile: a floor margin, a one-pixel outline, a
  fill and a white "?" (16 x 16 mask, in maze space, so it turns with the
  map). Buff: blue fill 0x04F, green outline 0x0F0. Debuff: red fill 0xC00,
  light-red outline 0xF88. The start (solid red) and goal (solid green) are
  unchanged and drawn first.
- `render` has a `box_visible[3:0]` input for Story 9.2; the top ties it high.
- The maze memory is unchanged; boxes are not obstacles.

## Simulation (Vivado 2025.2)

- `tb_maze_gen`: PASS, 563 runs. Every N >= 4 run has four valid boxes, one
  per quadrant, on free floor cells that are not the start or goal; N = 2 and
  3 have none; `box_valid` is clear after `gen_start`; all six buff quadrant
  pairs occur; box positions are included in the same-seed determinism hash.
  Longest generation 2,559 cycles.
- `tb_render`: PASS. On the fixed-seed HARD maze it checks that all four box
  positions fall inside the map, and on each box's centre scanline the floor
  margin, outline, fill and "?" pixel.
- `tb_rotated_render`: PASS. Two boxes on its fixed map are checked pixel by
  pixel against an independent model of the 16 x 16 mask, at 0 degrees and,
  turned with the map, at 90 degrees (1,046 box pixels), plus sparse samples
  at 45 and 135 degrees. A box hidden by `box_visible` and a box without
  `box_valid` must not be drawn. Two mutants are caught: dropping the top and
  bottom margin rows, and a wrong "?" row.
- The other benches that instantiate `render` directly tie the box inputs off.
- `tb/run_current_stories.tcl`: PASS, exit code 0, 40 PASS lines (rerun after the review fixes).

## Routed build

`scripts/check_timing.tcl` (100 MHz), after the review fixes: timing met.
WNS +0.725 ns (main +1.004 ns), WHS +0.087 ns. 3,722 LUTs (main 3,648),
3,806 registers (main 3,748), 2.5 block RAM tiles, 6 DSPs.
That is 17.9% of LUTs, 9.2% of flip-flops, 2.5 of 6 block RAM tiles and 6 of
8 DSPs, all within the AD-8 caps (50%, 30%, 6, 8). The worst path is in the
OLED text mailbox, not the new logic.

## Review and board check

Three review subagents (blind, edge-case and verification-gap) read the diff.
Their findings and verdicts are in the spec's Review Triage Log; the fixes
were the rotated-render box checks, clearing the box coordinates, and this
file's wording. A box sitting next to the start or goal is deferred to 9.2 or
9.8 (`deferred-work.md`).

The board check is not done. It needs a teammate other than DY.
