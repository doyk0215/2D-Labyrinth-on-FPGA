story_id: 7.1
story_key: 7-1-map-size-follows-the-stage
title: Map size follows the stage
status: review
owner: QZ
epic: 7
depends_on: []
source_issue: https://github.com/doyk0215/2D-Labyrinth-on-FPGA/issues/53
---

# Story 7.1: Map size follows the stage

As a developer,
I want map dimensions to follow the stage instead of being fixed at 21 x 21,
so that a larger stage needs no structural redesign.

## Story Context

The current RTL uses a fixed 21 x 21 tile map, 9-bit tile addresses, and a
fixed-depth maze-generation stack. Story 7.1 expands the supported stage size
through N = 15, where the maze occupies a 31 x 31 tile map. This affects the
shared map dimensions and address width, centered placement, maze RAM, maze
generator, renderer, and ball physics. The generator must have enough stack
capacity for all 225 cells at N = 15.

The map must remain centered around its geometric center as its dimensions
change. Existing N = 5 and N = 10 simulations are compatibility checks: their
behavior and regression results must remain unchanged. QZ owns this story.

## Acceptance Criteria

1. **Size the map for the stage**
   - Replace fixed 21 x 21 sizing with stage-dependent dimensions of 2N + 1
     tiles per side, up to N = 15 (31 x 31).
   - Set the tile address width to cover every tile; the N = 15 map requires
     10 bits for addresses 0 through 960.
   - Derive maze centering offsets and related coordinate calculations from
     the selected dimensions so rendering, physics, and generation agree on
     the map center.
   - Provide storage for the complete map and use a generator DFS stack that
     can hold all 225 N = 15 cells without overflow.

2. **Preserve the existing maze-generation contract**
   - Generate perfect, solvable mazes for N = 15 across many seeds.
   - Never overflow the generation stack.
   - Generation is deterministic for a given seed.

3. **Preserve physics behavior at the larger map size**
   - Run the existing bounce, tunnelling, and goal-detection checks using
     ball physics on an N = 15, 31 x 31 map; all must pass.

4. **Retain existing stage regressions**
   - Existing N = 5 and N = 10 regression tests pass without changing their
     expected behavior.

## Interface and Design Notes

- Keep tile addresses consistent across `labyrinth_pkg.vh`, `maze_ram`,
  `maze_gen`, `render`, `ball_physics`, and their testbenches. A 31 x 31 map
  contains 961 tiles and needs 10 address bits.
- The largest maze has 15 x 15 = 225 logical cells. Size the depth-first
  search stack and its pointer for the full legal depth; verify the final push
  and pop boundary explicitly.
- Compute map center and any centering offset from the selected N/map size.
  Check tile-to-pixel offsets and start/goal coordinates at N = 5, 10, and 15.
- The implementation uses maximum 31 x 31 RAM capacity with a stage-dependent
  active extent and packed row stride `(2*N+1)`. All consumers receive the
  selected N and use the same active bounds and address calculation.
- Update memory depth and address arithmetic consistently; avoid truncation
  in row-times-width calculations and comparisons at address 960.
- Preserve the maze-generation seed contract and the current start/goal
  semantics while scaling coordinates.

## Implementation Tasks

- [x] Audit all fixed 21 x 21, 9-bit address, fixed centering, and fixed stack
      assumptions in the package, RAM, generator, renderer, physics, and tests.
- [x] Implement stage-dependent map sizing through N = 15, including address
      width, center offsets, RAM capacity, and the 225-entry DFS stack.
- [x] Extend generator coverage to many N = 15 seeds; check determinism,
      connectivity/perfect-maze properties, and stack bounds.
- [x] Run existing N = 5 and N = 10 maze and system regressions unchanged.
- [x] Run N = 15 bounce, tunnelling, and goal-detection physics tests.
- [x] Run the Story 7.1 focused Vivado testbench and record the Vivado version
      and results below.
- [ ] Record synthesis/resource implications for the larger map if required
      by the project regression workflow.

## Definition of Done

- The map dimensions and all dependent address/coordinate calculations
  support every stage through N = 15.
- Maze RAM and renderer/physics map access correctly cover all 961 tiles.
- The generator completes N = 15 mazes for many seeds without stack overflow;
  mazes are perfect and solvable, and output is deterministic per seed.
- N = 15 bounce, tunnelling, and goal tests pass.
- Existing N = 5 and N = 10 regressions pass unchanged.
- The focused Vivado results and any material resource changes are recorded,
  and the implementation is reviewed and merged by pull request.

## Implementation Evidence

Implemented the stage-dependent packed map through N = 15: 31 x 31 tiles,
961 RAM entries, 10-bit tile addresses, dynamic map centering and row stride,
and a 225-entry maze-generation stack. RAM is initialized as wall tiles and
the fixed 21 x 21 maze is copied into its matching addresses for compatibility
with the default stage. Physics, rendering, goal checks, and top-level
connections now use the selected stage dimension.

Verified with AMD Vivado 2025.2:

- `tb/run_story71.tcl`: PASS. Goal detection covers N = 2..15; maze generation
  checked 557 total cases (including many N = 15 seeds), with every maze
  perfect, solvable, and deterministic per seed. Maximum observed DFS depth
  was 170 of 225 entries; longest generation was 2,465 cycles. N = 15 renderer
  address 960 and active bounds passed. N = 15 physics bounce, no-tunnelling,
  and goal-bound checks passed; the existing N = 10 physics suite also passed.
- `tb/run_current_stories.tcl`: PASS, exit code 0. Existing Story 1.1 through
  4.4 regressions passed, including N = 5 and N = 10 coverage, the Story 2.1
  top-level PS/2 integration check, ball/top integration, and both OLED display
  modes.

No FPGA synthesis/resource report or physical board test was run for this
story. The test results establish simulation coverage only.

## Review change: fixed 32-tile row (DY, 2026-10-31)

Merged with `main` (Stories 6.1, 8.1 and 9.6), the packed layout failed
routed timing at 100 MHz: WNS -0.911 ns on the physics read address, where
`row * (2N+1)` became a long LUT carry chain. Two changes fix it:

- The maze is stored at `addr = {row, col}` (a fixed 32-tile row, 1,024
  tiles) on every stage. Physics, the generator and the renderer no longer
  multiply; the generator clears all 1,024 tiles; the 21 x 21 fixed map is
  placed in rows and columns 0..20. `MAP_STRIDE` is added to the package.
- `ball_physics` registers its map-edge test (`oob_r`) in `S_READ0` with the
  other per-axis results, as the compare against the stage size came after
  the move adders.

The benches use the 32-tile row (`tb_maze_gen`, `tb_ball_physics`,
`tb_story71_*`, `tb_render`, `tb_rotated_render`, `tb_top_ball`,
`tb_top_story14/33`), and `docs/parallel-workstreams.md` records the new
maze memory contract.

Vivado 2025.2 on the merged result: `tb/run_current_stories.tcl` PASS (33
PASS lines, both OLED modes). Routed `scripts/check_timing.tcl`: WNS +0.524 ns,
WHS +0.097 ns, all constraints met; 3,336 LUTs, 3,530 registers, 2.5 BRAM
tiles, 6 DSPs (main: +0.366 ns, 2,958 LUTs, 2,603 registers, 1.5 BRAM).
The extra registers come mostly from the 225-entry generator stack. Board
test still to do.
