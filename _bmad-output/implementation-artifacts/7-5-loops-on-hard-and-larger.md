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

The target loop counts are fixed by stage: HARD removes 5 interior walls and
N = 15 removes 7. With `N*N` cells, loop stages must contain exactly
`N*N - 1 + K` open cell-to-cell connections. Generation must remain
deterministic for a given seed, connected, and solvable. `maze_gen` remains the
only writer of `maze_ram`.

Story 7.1 is the only prerequisite. The current shared map uses a fixed
32-tile row (`addr = {row, col}`), with the active `(2N+1) x (2N+1)` map in
the top-left and center tile N. The existing difficulty and stage selection
must determine whether K is zero, five, or seven without changing EASY
behavior.

## Acceptance Criteria

1. **Add a fixed number of loops to HARD and N = 15**
   - HARD generation removes exactly 5 distinct interior walls between floor
     cells after the perfect-maze backbone is generated.
   - N = 15 generation removes exactly 7 distinct interior walls between
     floor cells.
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
      the intended K selection: EASY = 0, HARD = 5, N = 15 = 7.
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

- EASY remains a perfect maze; HARD has exactly five extra openings; N = 15
  has exactly seven extra openings.
- All generated mazes are connected and solvable, preserve the outer boundary,
  and are deterministic for a given seed.
- The generator remains the only writer of maze RAM.
- The architecture spine describes connected mazes with K additional
  openings on loop stages.
- Focused and current-stories Vivado regressions pass, and the non-author board
  check is recorded.

## Implementation Evidence

The generator now adds loops while its DFS visits new cells. A newly visited
cell exposes closed adjacencies to previously visited cells other than its DFS
parent; the seeded xorshift state selects an eligible direction. Each edge is
considered when its later endpoint is first visited, so an edge is never
opened twice. EASY opens zero additional walls, HARD (N = 10) opens five, and
N = 15 opens seven. All writes still use the existing `maze_gen` write port.

Verified with AMD Vivado 2025.2:

- `tb/run_story75.tcl`: PASS. 563 generator cases checked, including 200 HARD
  seeds, 25 seeds at every N from 2 through 15, exact edge counts, connected
  floor tiles, reachable goals, intact outer boundaries, and same-seed
  determinism at EASY, HARD, and N = 15. Maximum observed DFS depth was
  170/225 entries; longest generation was 2,535 cycles.
- `tb/run_current_stories.tcl`: PASS, exit code 0, including both OLED modes.
  The N = 10 renderer expectation was updated from 199 to 204 floor tiles to
  account for the five additional HARD passages.
- `tb/run_story14.tcl`: PASS. Its `tb_maze_gen` marker is now `PASS: maze_gen`,
  since this story changes the generator's PASS line.
- `scripts/check_timing.tcl` (routed, 100 MHz): timing met. WNS +0.323 ns
  (main +0.530 ns), WHS +0.055 ns. 3,840 LUTs (main 3,482), 3,702 registers
  (main 3,682), 2.5 block RAM tiles, 6 DSPs. The worst path is in the OLED text
  mailbox, not the generator.
- `git diff --check`: PASS.

No physical board test has been run. Issue #57 calls for that check to be
performed by a teammate other than the story author; it remains pending.
