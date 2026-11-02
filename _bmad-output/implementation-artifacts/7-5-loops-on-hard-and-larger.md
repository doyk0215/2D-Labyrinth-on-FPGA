---
story_id: 7.5
story_key: 7-5-loops-on-hard-and-larger
title: Loops on HARD and larger
status: review
owner: QZ
epic: 7
depends_on: [7.1]
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/57
---

# Story 7.5: Loops on HARD and larger

As the player,
I want harder stages to offer more than one route,
so that the maze is not a single path to follow.

## Story Context

The current maze generator uses a recursive-backtracker implemented as an
iterative FSM with an explicit stack. That produces a perfect maze: for `N*N`
logical cells, exactly `N*N - 1` cell-to-cell openings connect the maze. This
story preserves that behavior for EASY and allows a seeded number of additional
openings, up to a per-stage cap, for HARD and N = 15. A loop is created by
removing an interior wall between two logical cells that are already floors;
the outer wall boundary remains intact.

The loop caps are fixed by stage: HARD (N = 10) may remove up to 3 interior
walls and N = 15 up to 5 (decided by DY on 2026-11-01 after review, down from 5
and 7; see Loop placement below). With `N*N` cells, loop stages contain between
`N*N - 1` and `N*N - 1 + K` open cell-to-cell connections. Any added loops stay
spread across the existing row bands, with no more than one loop in a band.
Generation remains deterministic for a given seed, connected, and solvable.
`maze_gen` remains the only writer of `maze_ram`.

Story 7.1 is the only prerequisite. The current shared map uses a fixed
32-tile row (`addr = {row, col}`), with the active `(2N+1) x (2N+1)` map in
the top-left and center tile N. The existing difficulty and stage selection
must determine whether the cap is zero, three, or five without changing EASY
behavior.

## Acceptance Criteria

1. **Allow up to a capped number of loops on HARD and N = 15**
   - HARD generation removes 0..3 distinct interior walls between floor
     cells after the perfect-maze backbone is generated.
   - N = 15 generation removes 0..5 distinct interior walls between floor
     cells.
   - A seeded optional loop is considered in each existing band of cell rows,
     from the goal side to the start side; each selected band has at most one.
   - EASY generation removes no walls and remains a perfect maze.
   - The outer map boundary remains walls for every stage.
   - `maze_gen` remains the only writer of `maze_ram`.

2. **Preserve connectivity and reachability**
   - Across many seeds, EASY mazes have exactly `cells - 1` cell-to-cell
     openings; HARD and N = 15 have between `cells - 1` and `cells - 1 + K`.
   - Every generated maze remains connected, and its start and goal remain
     reachable.
   - A repeated run with the same seed produces identical map contents.

3. **Update the architecture spine**
   - Replace the unconditional “perfect-maze property guarantees solvability”
     wording with the rule that mazes are connected, with K extra openings on
     loop stages.

4. **Verify in Vivado and on the board**
   - Add or update a self-checking generator regression covering EASY, HARD,
     and N = 15 over many seeds, including loop count, boundary integrity,
     connectivity, reachability, and deterministic output.
   - Run the Story 7.5 Vivado regression and the current-stories regression.
   - Record the Vivado version and results. The board check is performed by a
     teammate other than the story author, per issue #57's workflow.

## Interface and Design Notes

- The logical maze has `N*N` cells embedded in a `(2N+1) x (2N+1)` active
  tile map; physical RAM uses the shared fixed 32-tile row.
- Count loops as additional open adjacencies between logical cells, not as
  the number of floor tiles or arbitrary wall-to-floor transitions.
- Select each loop by opening a distinct interior wall separating two
  adjacent logical cells. Never select an outer boundary tile or count the
  same wall twice.
- Use only seeded generator state for loop selection so identical seeds stay
  deterministic. Preserve the generator's existing seed contract.
- Keep all map writes in the existing `maze_gen` write interface; do not add a
  second writer in the top level or another module.
- Update the architecture spine at
  `_bmad-output/planning-artifacts/architecture/architecture-2D-Labyrinth-on-FPGA-2026-10-23/ARCHITECTURE-SPINE.md`.

## Implementation Tasks

- [x] Trace stage difficulty and N through the current generator and confirm
      the caps: EASY = 0, HARD = 3, N = 15 = 5.
- [x] Add seeded selection of up to the cap, with at most one distinct
      interior wall opened in each existing band after the perfect-maze pass.
- [x] Preserve outer walls and keep `maze_gen` as the sole RAM writer.
- [x] Extend generator tests to count openings, prove connectivity and
      start/goal reachability, check determinism, and assert the boundary for
      many seeds across EASY, HARD, and N = 15.
- [x] Update the architecture spine's maze-generation rule.
- [x] Run the updated focused Story 7.5 Vivado regression and current-stories
      regression for the cap behavior.
- [ ] Coordinate a physical board check with a non-author teammate and record
      the outcome.

## Definition of Done

- EASY remains a perfect maze; HARD has at most three extra openings and N=15
  at most five, with any loops distributed one per existing row band.
- All generated mazes are connected and solvable, preserve the outer boundary,
  and are deterministic for a given seed.
- The generator remains the only writer of maze RAM.
- The architecture spine describes connected mazes with K additional
  openings on loop stages.
- Focused and current-stories Vivado regressions pass, and the non-author board
  check is recorded.

## Implementation Evidence

The generator first builds the perfect maze, unchanged from Story 1.3: the
spanning tree is the same as before for every seed, and EASY is bit-for-bit
unchanged. While it carves passages it records which east and south walls it
opened (two 256 x 1 LUT RAMs, cleared during the map clear). A loop pass then
runs after the search: band k covers cell rows 3k..3k+2, the last band takes
any leftover rows, and each band's seeded selection decides whether that band
gets a loop. Selected bands choose a seeded start position and scan their
interior walls (east, then south, wrapping) until a closed one is found and
opened. Thus at most one loop is added in each band. HARD (N = 10) has three
bands and N = 15 has five; every other N, including EASY, gets none. All writes
still use the existing `maze_gen` write port.

**Loop placement background (review of PR #77, decided by DY on 2026-11-01).**
The following route-coverage measurements are from the fixed-count version,
before the current follow-up made bands optional. The PR as
first opened opened a loop at each of the first K chances during the search.
The search starts at the goal, so every loop landed in the first quarter of the
build, next to the goal. A route-coverage probe (block each tile of the
shortest start-goal route in turn and check whether the goal is still
reachable; 50 seeds per size, RTL simulation) gave:

| Version | Route tiles with a way round | Start half | Goal half | Mazes with a way round in the start half |
|---|---|---|---|---|
| First version, N = 10, K = 5 | 8% | 2% | 15% | 13 of 50 |
| Band pass, N = 10, K = 3 | 26% | 29% | 23% | 39 of 50 |
| First version, N = 15, K = 7 | 5% | 0% | 11% | 3 of 50 |
| Band pass, N = 15, K = 5 | 27% | 32% | 21% | 47 of 50 |

With fewer loops, the band pass gives a way round about three times as much of
the route, and on both halves of it. A loop can still land on a dead-end branch
and miss the route: 3 of 50 HARD mazes and 2 of 50 N = 15 mazes had no way
round any route tile.

The cap-based follow-up was simulated with AMD Vivado 2025.2 on 2026-11-02.
The focused generator run checked 763 generated mazes; HARD and N = 15 each
exercised both below-cap and at-cap outcomes. The current-stories regression
also completed, including the updated renderer and WIN overlay benches and both
OLED display modes. The FPGA bitstream is built separately after committing
these source changes.

- `tb/run_story75.tcl`: PASS, 763 generator cases. EASY remained perfect;
  HARD (N = 10) and N = 15 stayed within their caps, with both zero-loop and
  at-cap results exercised. Checks cover band limits, connected floor tiles,
  reachable goals, intact outer boundaries, and same-seed determinism.
  Maximum observed DFS depth was 180/225 entries; longest generation was
  2,581 cycles.
- Mutation checks against `tb_maze_gen`: putting every loop in band 0 gives 659
  FAIL lines; opening walls without checking they are closed gives 662.
- `tb/run_current_stories.tcl`: PASS with both OLED display modes. This
  regression includes the cap-aware renderer expectation, generator bench,
  updated WIN overlay text, and current top-level/story benches.
- `tb/run_story14.tcl`: PASS. Its `tb_maze_gen` marker is now `PASS: maze_gen`,
  since this story changes the generator's PASS line.
- `scripts/check_timing.tcl` (routed, 100 MHz): timing met. WNS +0.235 ns
  (main +0.530 ns), WHS +0.037 ns. 3,580 LUTs (main 3,482; 16 as LUT RAM),
  3,704 registers (main 3,682), 2.5 block RAM tiles, 6 DSPs. The worst path is
  in the OLED text mailbox, not the generator.
- `git diff --check`: PASS.

No physical board test has been run. Issue #57 calls for that check to be
performed by a teammate other than the story author; it remains pending.
