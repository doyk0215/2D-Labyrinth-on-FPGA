# Work Order — 2D Labyrinth on FPGA

Owners: **DY** = stream A (physics, maze generation, OLED driver), **QZ** = stream B (input and game control), **CJX** = stream C (graphics, top level). DY also runs every hardware check.
Story details: `_bmad-output/planning-artifacts/epics.md`. Interfaces: `docs/parallel-workstreams.md`, section 3.

"Needs" means the story cannot be finished or verified without that item, either the real module or an agreed stub from the interface contract.

## Phase 0 — done
| Step | Who | What | Status |
| --- | --- | --- | --- |
| 0 | DY | `rtl/labyrinth_pkg.vh`, folder layout, `constraints/basys3.xdc`, `scripts/create_project.tcl` | Done and pushed |

## Phase 1 — week 1
| Story | Owner | Needs |
| --- | --- | --- |
| 1.1 Project skeleton and VGA picture | CJX | step 0 (check the XDC pins against Digilent's master XDC first) |
| `sincos_rom` (part of 2.2) | DY | step 0 |
| 2.1 Mouse and input | QZ | step 0 (board test also needs 1.1's XDC and `top.v`) |
| 1.2 Fixed maze drawn | CJX | 1.1 |
| 1.3 Maze generator | DY | `maze_ram` write port from 1.2 (simulate against a stub first) |
| 2.2 Angle accumulator | QZ | `sincos_rom` |
| 4.1 OLED text driver | DY | 1.1 for pins (simulate first) |
| 1.4 Game state skeleton | QZ | 1.3 (and 1.2 to see it on screen) |

**Integration check 1 (DY, end of week 1):** video, mouse, angle, generator and OLED text each work on the board.

## Phase 2 — week 2
| Story | Owner | Needs |
| --- | --- | --- |
| 2.3 Rotated render | CJX | 1.2, `sincos_rom`, 2.2 (use a switch-driven angle until 2.2 lands) |
| 3.1 Ball falls under gravity | DY | `sincos_rom`, 1.3 (start tile), 1.2 (map read); drawing the ball needs 2.3 |
| 3.2 Collisions | DY | 3.1 |
| 3.3 Win and play again | QZ (control) + CJX (win picture) | 1.4, 3.2 (goal test), 1.3 |
| 3.4 Reset and frame budget | QZ | 3.3 |
| 2.4 Snap-rotation fallback | CJX | 2.3, 2.1 |

**Integration check 2 (DY, end of week 2):** the ball plays on the board. If 2.3 is not working by then, use 2.4 as the fallback.

## Phase 3 — week 3
| Story | Owner | Needs |
| --- | --- | --- |
| 4.2 Stage select | QZ | 4.1, 1.4 |
| 4.3 Settings | QZ | 4.2 |
| 4.4 Live status and timer | QZ | 4.2, 3.3 |
| 5.1 Timing and resources | CJX | all modules in |
| 5.2 Testbench regression | all | every testbench exists |
| 5.3 Demo script | all | 3.4, 4.4 |
| 5.4 Report | all | 5.1, 5.2 |

## Chains to watch
1. 1.1 → 1.2 → 2.3 → 3.1's ball drawing → 2.4 (longest chain, all CJX).
2. `sincos_rom` → 2.2 → 3.1 → 3.2 → 3.3 → 3.4.
3. 4.1 → 4.2 → 4.3 and 4.4 (has slack).

A slip in the first story of a chain delays everything after it. `sincos_rom` (DY) and Story 1.1 (CJX) unblock the others on day one, so do them first.

## Git workflow (mandatory)
- **All work happens on a feature branch, never directly on `main`.** One branch per story, named `feature/<story-number>-<short-name>` (for example `feature/1-1-vga-timing`, `feature/3-1-ball-gravity`). Documentation-only changes use `docs/<short-name>`.
- **Nothing reaches `main` except through a pull request.** Push the feature branch to `origin` and open a PR into `main`. Do not push to `main` directly, and do not force-push.
- Each PR covers one story (or one part of a story), references the story number, and lists which testbenches pass. The owner of any interface the PR touches reviews it; DY also runs the hardware check where the story needs the board.
- Merge only when the PR builds in Vivado 2025.2 without errors and its testbenches print PASS.
- Keep branches short-lived: merge the PR, then delete the branch, so the next story starts from an up-to-date `main`.
- Recommended: turn on GitHub branch protection for `main` (require a pull request before merging) so the rule is enforced and not only agreed.

## Other working rules
- One owner per file; the interface contract is frozen (changes need all three owners).
- Hardware checks: send DY the branch name and story number (or a `.bit` file); DY reports PASS or FAIL with a photo or note.
