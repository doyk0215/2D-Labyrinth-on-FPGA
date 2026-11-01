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
story preserves that behavior for EASY and adds a fixed number of additional
openings for HARD and the N = 15 stage. A loop is created by removing an
interior wall between two logical cells that are already floors; the outer
wall boundary remains intact.

The target loop counts are fixed by stage: HARD removes 3 interior walls and
N = 15 removes 5 (decided by DY on 2026-11-01 after review, down from 5 and
7; see Loop placement below). With `N*N` cells, loop stages must contain exactly
`N*N - 1 + K` open cell-to-cell connections. Generation must remain
deterministic for a given seed, connected, and solvable. `maze_gen` remains the
only writer of `maze_ram`.

Story 7.1 is the only prerequisite. The current shared map uses a fixed
32-tile row (`addr = {row, col}`), with the active `(2N+1) x (2N+1)` map in
the top-left and center tile N. The existing difficulty and stage selection
must determine whether K is zero, three, or five without changing EASY
behavior.

## Acceptance Criteria

1. **Add a fixed number of loops to HARD and N = 15**
   - HARD generation removes exactly 3 distinct interior walls between floor
     cells after the perfect-maze backbone is generated.
   - N = 15 generation removes exactly 5 distinct interior walls between
     floor cells.
   - The loops are spread over the maze: one in each band of cell rows, from
     the goal side to the start side.
   - EASY generation removes no walls and remains a perfect maze.
   - The outer map boundary remains walls for every stage.
   - `maze_gen` remains the only writer of `maze_ram`.

2. **Preserve connectivity and reachability**
   - Across many seeds, EASY mazes have exactly `cells - 1` cell-to-cell
     openings; HARD and N = 15 mazes have exactly `cells - 1 + K`.
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
      the intended K selection: EASY = 0, HARD = 3, N = 15 = 5.
- [x] Add seeded, bounded selection of the required number of distinct
      interior walls after the perfect-maze generation pass.
- [x] Preserve outer walls and keep `maze_gen` as the sole RAM writer.
- [x] Extend generator tests to count openings, prove connectivity and
      start/goal reachability, check determinism, and assert the boundary for
      many seeds across EASY, HARD, and N = 15.
- [x] Update the architecture spine's maze-generation rule.
- [x] Run the focused Story 7.5 Vivado regression and current-stories
      regression; record Vivado version and results.
- [ ] Coordinate a physical board check with a non-author teammate and record
      the outcome.

## Definition of Done

- EASY remains a perfect maze; HARD has exactly three extra openings; N = 15
  has exactly five extra openings, one per row band.
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
any leftover rows, and for each band a seeded start position is chosen and the
band's interior walls are scanned (east, then south, wrapping) until a closed
one is found and opened. A band of R rows always has at least (R-1)(N-1) closed
interior walls, so the count is exact and the pass takes at most 2RN cycles per
band. HARD (N = 10) gets 3 loops (bands 0-2, 3-5, 6-9) and N = 15 gets 5 (five
bands of 3 rows); every other N, including EASY, gets none. All writes still
use the existing `maze_gen` write port.

**Loop placement (review of PR #77, decided by DY on 2026-11-01).** The PR as
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

Verified with AMD Vivado 2025.2:

- `tb/run_story75.tcl`: PASS. 563 generator cases checked, including 200 HARD
  seeds, 25 seeds at every N from 2 through 15, exact edge counts, one loop per
  band (the last K floor writes are interior walls inside bands 0..K-1),
  connected floor tiles, reachable goals, intact outer boundaries, and same-seed
  determinism at EASY, HARD, and N = 15. Maximum observed DFS depth was
  170/225 entries; longest generation was 2,553 cycles.
- Mutation checks against `tb_maze_gen`: putting every loop in band 0 gives 659
  FAIL lines; opening walls without checking they are closed gives 662.
- `tb/run_current_stories.tcl`: PASS, exit code 0, 38 PASS lines, including
  both OLED modes. The N = 10 renderer expectation was updated from 199 to 202
  floor tiles for the three HARD loops.
- `tb/run_story14.tcl`: PASS. Its `tb_maze_gen` marker is now `PASS: maze_gen`,
  since this story changes the generator's PASS line.
- `scripts/check_timing.tcl` (routed, 100 MHz): timing met. WNS +0.235 ns
  (main +0.530 ns), WHS +0.037 ns. 3,580 LUTs (main 3,482; 16 as LUT RAM),
  3,704 registers (main 3,682), 2.5 block RAM tiles, 6 DSPs. The worst path is
  in the OLED text mailbox, not the generator.
- `git diff --check`: PASS.

No physical board test has been run. Issue #57 calls for that check to be
performed by a teammate other than the story author; it remains pending.
