---
status: final
stepsCompleted: ['step-01-validate-prerequisites', 'step-02-design-epics', 'step-03-create-stories']
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-2D-Labyrinth-on-FPGA-2026-10-23/prd.md
  - _bmad-output/planning-artifacts/architecture/architecture-2D-Labyrinth-on-FPGA-2026-10-23/ARCHITECTURE-SPINE.md
---

# 2D-Labyrinth-on-FPGA - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for 2D-Labyrinth-on-FPGA, decomposing the requirements from the PRD and the Architecture spine into implementable stories. There is no UX document; the VGA picture and OLED text menu are specified in the PRD and spine.

## Requirements Inventory

### Functional Requirements

FR1: The system generates a new random maze on power-up and after each win.
FR2: Every generated maze is solvable from the start to the goal (perfect-maze algorithm).
FR3: Randomness comes from a hardware PRNG (LFSR) seeded from a source that varies between runs.
FR4: The start cell and goal cell are visually distinct from each other and from the maze.
FR5: While the left mouse button is held the maze rotates counter-clockwise at a constant angular speed (about 90°/s); while the right button is held it rotates clockwise.
FR6: Releasing the button stops the rotation immediately and the maze holds its angle; both buttons or neither means no rotation.
FR7: The angle is continuous and wraps at 360°; the maze is drawn at its exact angle every frame using a sine/cosine table.
FR8: Gravity always points down on screen; in the maze frame it rotates with the opposite angle, including mid-rotation.
FR8b: Physics runs in the maze frame with rotating gravity only; centrifugal, Coriolis and moving-wall effects are ignored (stated in the report).
FR9: Gravity is constant and points down on screen at all times.
FR10: The ball moves with fixed-point position and velocity, updated once per frame.
FR11: On wall collision the normal velocity component reverses and is scaled by a restitution below 1 (about 0.5 to 0.7).
FR12: No friction: tangential velocity is unchanged by collisions and no drag is applied.
FR13: The ball never passes through or gets stuck inside a wall (a speed cap may apply).
FR14: When the maze rotates the ball keeps its position relative to the maze and feels the effective gravity every frame; collisions run in the maze frame.
FR15: Reaching the goal cell triggers a win state, then a fresh random maze.
FR16: A reset button restores the initial state and generates a new maze.
FR17: A timer shows elapsed time for the current maze (optional; may use the OLED).
FR18: The display shows the maze, ball, start and goal at 60 frames per second without tearing.
FR19: The mouse is read through a PS/2 receiver; only the left and right button states are used.
FR20: The VGA/HDMI monitor shows the maze itself (maze, ball, start, goal, win state) and no menus.
FR21: The OLED module handles the menu, stage selection and settings, and is the only place they appear.
FR22: On power-up the OLED shows a menu; the player selects a stage with board buttons and starts the game.
FR23: A stage defines a maze difficulty (grid size and/or restitution); the OLED lists and shows the selected stage.
FR24: The OLED settings screen adjusts at least rotation speed (and optionally restitution); changes apply to the next game.
FR25: During play the OLED shows live status such as stage number and elapsed time.
FR26: The game starts only after a stage is chosen on the OLED; a reset returns to the menu.

### NonFunctional Requirements

NFR1: Timing closure at the 100 MHz board clock and the 25 MHz pixel enable with no failing paths.
NFR1b: The VGA signal is compatible with the VGA-to-HDMI converter (standard 640×480 @ 60 Hz timing).
NFR2: The physics update completes within one frame so the game never stutters.
NFR3: The design fits the board's resources with headroom (budget in AD-8).
NFR4: Modular design with separate blocks for mouse input, maze generation, rotation, physics, rendering, display timing, OLED driver and menu control, each with a simulation testbench.
NFR5: Behaviour is reproducible: the same PRNG seed gives the same maze.

### Additional Requirements

- No starter template. Epic 1 Story 1 is project setup: Vivado 2025.2 project for XC7A35T-1CPG236C, plain Verilog-2005, one XDC (`constraints/basys3.xdc`), `labyrinth_pkg.vh`, top-level wrapper.
- AD-1: No framebuffer; pixels are computed in the beam (line buffer at most 640×12 bits).
- AD-2: Single 100 MHz clock domain; `ce_pix` is a 1-in-4 enable; async inputs get two-flip-flop synchronizers; no derived clocks or MMCM.
- AD-3: Physics in maze coordinates; gravity in maze frame from the same sincos as the renderer; ball drawn round in screen space.
- AD-4: All fixed-point formats in `labyrinth_pkg.vh` (12-bit angle, Q1.14 trig with 256-entry quarter table, Q9.8 positions, Q4.8 velocities, 16 px tiles, 21×21 tile map, ball radius 5 px, speed cap 7 px/frame, shift-add restitution).
- AD-5: Single writer per shared state (`maze_ram`: `maze_gen`; angle/ball: `game_ctrl` datapath; `game_cfg`/`status_text`: `menu_ctrl`).
- AD-6: State changes only on `frame_tick` (start of vertical blanking); renderer reads latched snapshots.
- AD-7: Incremental affine render walk (per-scanline setup, per-pixel adds, fixed latency, nearest-neighbour).
- AD-8: Resource budget on XC7A35T: LUTs ≤ 50%, flip-flops ≤ 30%, block RAM ≤ 6, DSP48 ≤ 8, no clock tiles.
- AD-9: `input_mux` outputs `rot_cmd` (−1/0/+1); PS/2 stream mode with enable 0xF4; BTNL/BTNR fallback.
- AD-10: OLED text-only: 4×16 character buffer, SSD1306 init, SPI ≤ 10 MHz, power sequence per Digilent manual; menu on BTNU/BTND/BTNC.
- AD-11: Collision by per-axis move and tile test with clamp and restitution; goal = ball centre in goal tile.
- AD-12: Maze generation by iterative DFS with explicit stack, only in GENERATE state; seed from free-running counter or debug fixed seed.
- AD-13: Every module has a self-checking testbench (maze solvability by BFS, physics no-tunnelling and bounce ratio, PS/2 packet stream, VGA timing counts, render pixel checks).
- File layout: `rtl/`, `tb/`, `constraints/` as in the spine's Structural Seed; game states MENU, GENERATE, PLAY, WIN.

### UX Design Requirements

None (no UX document).

### FR Coverage Map

FR1: Epic 1 - Random maze generated on power-up and after a win (re-generation hook in Epic 3)
FR2: Epic 1 - Guaranteed solvable maze
FR3: Epic 1 - Hardware PRNG seeding
FR4: Epic 1 - Distinct start and goal cells
FR5: Epic 2 - Hold left/right to rotate
FR6: Epic 2 - Release stops, both/neither = none
FR7: Epic 2 - Continuous angle, sine/cosine rendering
FR8: Epic 3 - Gravity down on screen, rotating in maze frame
FR8b: Epic 3 - Rotating-gravity-only physics simplification
FR9: Epic 3 - Constant gravity
FR10: Epic 3 - Fixed-point ball update per frame
FR11: Epic 3 - Elastic wall bounce
FR12: Epic 3 - No friction
FR13: Epic 3 - No tunnelling or sticking
FR14: Epic 3 - Ball fixed to maze, collisions in maze frame
FR15: Epic 3 - Win state and new maze
FR16: Epic 3 - Reset (to a new maze; to the menu once Epic 4 lands)
FR17: Epic 4 - Elapsed-time timer
FR18: Epic 1 - 60 fps tear-free display
FR19: Epic 2 - PS/2 mouse button reading
FR20: Epic 1 - Maze view on the monitor only
FR21: Epic 4 - Menus only on the OLED
FR22: Epic 4 - OLED menu at power-up
FR23: Epic 4 - Stage selection
FR24: Epic 4 - Settings screen
FR25: Epic 4 - Live status on the OLED
FR26: Epic 4 - Start only after a stage is chosen

NFR1, NFR3 and the final check of NFR4: Epic 5. NFR1b, NFR5: Epic 1. NFR2: Epic 3. NFR4 is also applied per module in every epic.

## Epic List

### Epic 1: A random maze on the monitor
The examiner powers on the board and sees a freshly generated, solvable random maze with distinct start and goal on the HDMI monitor.
**FRs covered:** FR1, FR2, FR3, FR4, FR18, FR20

### Epic 2: Rotate the maze with the mouse
The player holds the left or right mouse button and the maze turns smoothly, stopping where released; the board buttons work as a fallback.
**FRs covered:** FR5, FR6, FR7, FR19

### Epic 3: Roll the ball to the goal
A ball falls under screen-down gravity, bounces slightly off walls with no friction, and reaching the goal wins and starts a new maze; reset works.
**FRs covered:** FR8, FR8b, FR9, FR10, FR11, FR12, FR13, FR14, FR15, FR16

### Epic 4: OLED menu, stages and settings
The player picks a stage and adjusts settings on the OLED and sees stage and timer during play.
**FRs covered:** FR17, FR21, FR22, FR23, FR24, FR25, FR26

### Epic 5: Demo-ready and report
The project is ready to be graded: timing closed, resource budget met, all testbenches passing, report and demo prepared.
**NFRs covered:** NFR1, NFR3, NFR4 (final check)

## Epic 1: A random maze on the monitor

The examiner powers on the board and sees a freshly generated, solvable random maze with distinct start and goal on the HDMI monitor.

### Story 1.1: Project skeleton and a stable VGA picture

**Starting point (recorded 2026-10-23):** Step 0 is already complete (done by DY): `rtl/labyrinth_pkg.vh`, the folder layout (`rtl/`, `tb/`, `constraints/`, `scripts/`), `constraints/basys3.xdc` and `scripts/create_project.tcl` (recreates the Vivado project). Story 1.1 starts from these files and does not recreate them. Remaining for 1.1: verify the XDC pins against Digilent's master XDC, write `top.v`, `vga_timing` and the test pattern, and check on the board.

As the examiner,
I want the board to show a stable test pattern on the HDMI monitor,
So that the video chain is proven before any game logic is built.

**Acceptance Criteria:**

**Given** a Vivado 2025.2 project for XC7A35T-1CPG236C with `rtl/`, `tb/`, `constraints/basys3.xdc` and `labyrinth_pkg.vh`
**When** the design is built and programmed
**Then** the monitor, via the VGA-to-HDMI converter, locks onto a 640×480 test pattern without manual setup (NFR1b)
**And** `vga_timing` produces `ce_pix` as a 1-in-4 enable of the single 100 MHz clock, with no derived clock and no MMCM (AD-2)

**Given** the `vga_timing` testbench
**When** it runs in batch
**Then** it reports PASS for 800×525 total counts, correct sync pulse widths, and exactly one `frame_tick` per frame at the start of vertical blanking (AD-6)

**Given** the implemented design
**When** the utilisation and timing reports are read
**Then** there are no timing failures and usage is within the AD-8 budget

### Story 1.2: Draw a fixed maze with distinct start and goal

As the examiner,
I want to see a maze with a clearly marked start and goal on the monitor,
So that the maze view and tile map are proven before generation is added.

**Acceptance Criteria:**

**Given** a `maze_ram` of 21×21 one-bit tiles and a hard-coded maze loaded into it
**When** the design runs
**Then** the maze is drawn axis-aligned at 16 px per tile (336×336 px) centred on the screen, walls and floor in different colours (FR18, FR20)
**And** the start tile and goal tile are each in a colour distinct from the walls, the floor and each other (FR4)

**Given** the render pipeline
**When** reviewed against AD-1 and AD-7
**Then** no screen-sized buffer exists, the per-pixel path contains no multiplier, and pixels outside the tile map are background

**Given** the `render` testbench
**When** it samples pixels at known positions
**Then** wall, floor, start, goal and background pixels match the expected colours

### Story 1.3: Generate a random solvable maze

As the examiner,
I want a different random maze each time the board starts or a new one is requested,
So that every game is new and always winnable.

**Acceptance Criteria:**

**Given** `maze_gen` (iterative DFS with explicit stack and a 32-bit LFSR, AD-12)
**When** it runs for a given seed and size N
**Then** it fills `maze_ram` with a perfect maze, sets the start and goal tiles, and signals done (FR1, FR2)
**And** an N-cell maze is stored centred in the 21×21 tile map (tiles 10−N to 10+N), everything else is wall
**And** `maze_gen` is the only writer of `maze_ram` (AD-5)

**Given** the `maze_gen` testbench
**When** it runs over at least 100 seeds
**Then** a BFS from start to goal succeeds for every maze (FR2)
**And** the same seed always produces the identical maze (NFR5)

**Given** the board running
**When** the seed source is selected
**Then** a debug switch gives a fixed seed, otherwise a free-running counter latched on the first user input gives a varying seed (FR3)

### Story 1.4: Game state skeleton and regenerate on demand

As the examiner,
I want to press a button to get a new random maze,
So that I can see that mazes differ and the flow is controlled by one state machine.

**Acceptance Criteria:**

**Given** `game_ctrl` with states MENU, GENERATE, PLAY and WIN
**When** the board powers up
**Then** it generates a maze and enters PLAY (temporarily skipping MENU until Epic 4)

**Given** the game is in PLAY
**When** a temporary board button is pressed
**Then** the game enters GENERATE, the monitor shows a different maze, and generation never runs while the renderer reads a half-built map

**Given** the design
**When** the state diagram is compared with the spine
**Then** states and transitions match, with a WIN to GENERATE transition left ready for Epic 3

## Epic 2: Rotate the maze with the mouse

The player holds the left or right mouse button and the maze turns smoothly, stopping where released; the board buttons work as a fallback.

### Story 2.1: Read the mouse and produce a rotation command

As the player,
I want my mouse buttons (or the board buttons) turned into a rotation command,
So that I can steer the maze.

**Acceptance Criteria:**

**Given** `ps2_mouse` with two-flip-flop synchronizers on the PS/2 lines
**When** it is reset
**Then** it sends the enable command 0xF4, receives the acknowledgement, and decodes 3-byte stream packets (FR19)
**And** it exposes only the left and right button bits and a `connected` flag (AD-9)

**Given** the `ps2_mouse` testbench with a recorded packet stream
**When** it runs
**Then** it reports PASS for left, right, both and no buttons

**Given** `input_mux`
**When** left is held, right is held, both or neither
**Then** `rot_cmd` is −1, +1, 0 and 0 respectively, with BTNL/BTNR giving the same results when no mouse is connected (FR5, FR6)
**And** LEDs show the current `rot_cmd` for bring-up on the board

### Story 2.2: Angle accumulator and sine/cosine table

As the player,
I want the maze angle to change smoothly while I hold a button and hold when I release,
So that rotation feels continuous.

**Acceptance Criteria:**

**Given** a 12-bit angle (4096 = 360°) updated only on `frame_tick` (AD-4, AD-6)
**When** `rot_cmd` is +1 for one second
**Then** the angle advances by about 90° (the default speed) and wraps at 360° (FR5, FR7)

**Given** `rot_cmd` returns to 0
**When** the next frame arrives
**Then** the angle stays exactly where it stopped (FR6)

**Given** `sincos_rom`, a 256-entry quarter-wave table in Q1.14 with symmetry
**When** its testbench compares 4096 angles with a software model
**Then** the maximum error is within the agreed tolerance (to be stated in the testbench)

### Story 2.3: Draw the maze at its exact angle

As the player,
I want the whole maze to be seen rotating on the monitor,
So that I can see what I am steering.

**Acceptance Criteria:**

**Given** the renderer with the incremental affine walk (AD-7)
**When** the angle changes
**Then** the maze is drawn rotated about the screen centre at that exact angle every frame, using a snapshot of the angle latched at frame start (FR7, AD-6)
**And** the maze stays fully on screen at every angle (half-diagonal 237 px < 240 px)

**Given** the render pipeline at angle 0
**When** compared with Story 1.2's output
**Then** the picture is pixel-identical

**Given** the `render` testbench at angles 0°, 45°, 90° and 135°
**When** sampled pixels are compared with a software model
**Then** they agree within one pixel of rotation error
**And** utilisation stays within the AD-8 budget (DSP48 ≤ 8, none in the per-pixel path)

### Story 2.4: Fallback 90° snap rotation mode

As the project owner,
I want a switch-selected snap mode,
So that I still have a demonstrable rotation if smooth rotation shows problems close to the deadline.

**Acceptance Criteria:**

**Given** a board switch set to snap mode
**When** a button is pressed and released
**Then** the angle moves to the next multiple of 90° in that direction and the maze is drawn there

**Given** the switch is off
**When** a button is held
**Then** the smooth behaviour of Stories 2.2 and 2.3 applies unchanged

**Given** the project report
**When** this fallback is listed
**Then** it is described as a fallback and not as the main feature

## Epic 3: Roll the ball to the goal

A ball falls under screen-down gravity, bounces slightly off walls with no friction, and reaching the goal wins and starts a new maze; reset works.

### Story 3.1: A ball that falls under screen-down gravity

As the player,
I want a ball that falls and rolls as I rotate the maze,
So that the maze behaves like a tilting game.

**Acceptance Criteria:**

**Given** the ball at the start tile, with position in Q9.8 and velocity in Q4.8 in maze coordinates (AD-3, AD-4)
**When** a frame arrives
**Then** velocity changes by gravity `g·(−sinθ, cosθ)` and the position changes by velocity, in the blanking interval (FR8, FR9, FR10, FR14)

**Given** the maze is rotated while the ball moves
**When** the ball is drawn
**Then** it is a round circle of radius 5 px at the rotated screen position of its maze position

**Given** the speed cap of 7 px per frame per axis (AD-4)
**When** gravity acts for a long time
**Then** no velocity component exceeds the cap
**And** `ball_physics` is the only writer of ball state (AD-5)

### Story 3.2: Elastic wall collisions without friction

As the player,
I want the ball to bounce slightly off walls and not slow down along them,
So that it feels like a bouncy ball on a smooth surface.

**Acceptance Criteria:**

**Given** the per-axis move and tile test (AD-11)
**When** the ball would enter a wall tile along x or y
**Then** it is clamped to the tile edge and that axis's velocity is reversed and scaled by the restitution using shifts and adds (FR11)
**And** the tangential velocity is unchanged and no drag is applied (FR12)

**Given** the `ball_physics` testbench
**When** the ball is fired at walls from many positions, speeds and angles up to the cap
**Then** it never ends inside a wall tile and never crosses a wall (FR13)
**And** the bounce speed ratio equals the configured restitution within quantisation error

**Given** the ball resting in a corner under gravity
**When** frames pass
**Then** it settles without jittering through the walls

### Story 3.3: Reach the goal, win, and play again

As the player,
I want a win when the ball reaches the goal and then a new maze,
So that the game has a point and can be replayed.

**Acceptance Criteria:**

**Given** the ball centre enters the goal tile
**When** the next frame is processed
**Then** `game_ctrl` enters WIN and the monitor shows a visible win indication (FR15, FR20)

**Given** WIN
**When** a short pause (about 2 s) elapses
**Then** a new maze is generated and the ball returns to the start (FR1)

**Given** the testbench with a scripted path
**When** the ball is placed in the goal tile
**Then** WIN is reached and then a new maze appears

### Story 3.4: Reset and frame-budget check

As the examiner,
I want a reset that always gives a clean new game and a game that never stutters,
So that a demo can be recovered and runs smoothly.

**Acceptance Criteria:**

**Given** any state
**When** the reset input is pressed
**Then** the ball, angle and timer are cleared and a new maze is generated (FR16); once Epic 4 lands, reset returns to the MENU state

**Given** the physics step
**When** measured in simulation and in the implementation report
**Then** it finishes within the vertical blanking interval (NFR2)

**Given** a bring-up session
**When** the ball is played for several minutes on the board
**Then** no picture tearing or stutter is seen (FR18)

## Epic 4: OLED menu, stages and settings

The player picks a stage and adjusts settings on the OLED and sees stage and timer during play.

### Story 4.1: Show text on the Pmod OLED

As the player,
I want the OLED to show readable text,
So that menus can be displayed there.

**Acceptance Criteria:**

**Given** `oled_driver` and `font_rom` with a 4×16 character buffer (AD-10)
**When** the board powers on
**Then** the SSD1306 is initialised using the power-up sequence of the Digilent Pmod OLED manual, and the buffer contents are shown with an 8×8 font over SPI with SCLK ≤ 10 MHz

**Given** the driver testbench
**When** it runs
**Then** it reports PASS for the init command order, the D/C and chip-select behaviour, and the byte stream for a sample text

**Given** a reset
**When** the board is powered down or reset
**Then** the OLED power-down order of the manual is followed

### Story 4.2: Choose a stage and start the game on the OLED

As the player,
I want to choose a stage on the OLED and start playing,
So that I control the difficulty.

**Acceptance Criteria:**

**Given** `menu_ctrl` in MENU state
**When** BTNU/BTND scrolls and BTNC confirms
**Then** the selected stage's settings (maze size N and restitution) are written to `game_cfg` and the game enters GENERATE (FR22, FR23, FR26)

**Given** the game has not started
**When** the monitor is observed
**Then** it shows no menu content and the game does not start until a stage is confirmed (FR20, FR21)

**Given** a stage with a smaller N
**When** the game starts
**Then** the generated maze and render use that N, centred and within the tile map

### Story 4.3: Settings screen

As the player,
I want to adjust rotation speed and optionally restitution,
So that the game feels the way I like.

**Acceptance Criteria:**

**Given** the settings screen on the OLED
**When** values are changed with the board buttons
**Then** the new rotation speed (and restitution, if included) is written to `game_cfg` (FR24)

**Given** a game is already in progress
**When** settings change
**Then** the change applies to the next game (latched at game start, AD-5)

**Given** the angle accumulator and physics
**When** the speed setting changes
**Then** all of its allowed values stay within the speed cap and keep the physics stable

### Story 4.4: Live status and timer on the OLED

As the player,
I want the stage and elapsed time shown on the OLED while I play,
So that I know how I am doing.

**Acceptance Criteria:**

**Given** the game is in PLAY
**When** time passes
**Then** the OLED shows the stage number and the elapsed time for the current maze, updated at least once per second (FR17, FR25)

**Given** a WIN or reset
**When** the state changes
**Then** the timer stops on WIN and clears on a new maze, and reset returns the OLED to the menu (FR16, FR26)

**Given** the OLED and game logic
**When** the design is reviewed
**Then** `oled_driver` reads only `status_text`; it never reads game state (AD-10)

## Epic 5: Demo-ready and report

The project is ready to be graded: timing closed, resource budget met, all testbenches passing, report and demo prepared.

### Story 5.1: Timing closure and resource report

As the project owner,
I want the final design to meet timing and the resource budget,
So that I can show the design is sound on the Basys 3.

**Acceptance Criteria:**

**Given** the full design in Vivado 2025.2
**When** implementation completes
**Then** there are no timing failures at 100 MHz and with the 25 MHz pixel enable (NFR1)

**Given** the utilisation report
**When** compared with AD-8
**Then** LUTs ≤ 50%, flip-flops ≤ 30%, block RAM ≤ 6, DSP48 ≤ 8, and no clock tiles are used (NFR3)
**And** the numbers are captured for the report

### Story 5.2: Full testbench regression

As the project owner,
I want one command that runs every testbench,
So that I can show all modules are verified.

**Acceptance Criteria:**

**Given** a testbench for each module (AD-13, NFR4)
**When** the batch regression runs
**Then** every testbench prints PASS and the run exits cleanly
**And** the list covers `vga_timing`, `maze_gen`, `ball_physics`, `ps2_mouse`, `render`, `sincos_rom`, `oled_driver` and `menu_ctrl`

**Given** the regression output
**When** saved
**Then** it is included in the report

### Story 5.3: Demo script and acceptance run

As the examiner,
I want a short, repeatable demo,
So that the grading criteria can be seen working.

**Acceptance Criteria:**

**Given** a prepared demo script
**When** it is followed on the board
**Then** the maze is generated, rotated by holding the mouse buttons, and the ball is brought to the goal on at least three different mazes

**Given** the OLED
**When** the demo starts
**Then** a stage is chosen on the OLED and a setting is changed once

**Given** a problem on the day
**When** the mouse fails
**Then** the board-button fallback and a reset recover the demo within a minute

### Story 5.4: Course report

As the project owner,
I want a report that explains the design and results,
So that the work can be graded.

**Acceptance Criteria:**

**Given** the finished project
**When** the report is written
**Then** it explains the architecture (the block diagram and the key decisions of the spine), the physics model, and the resource and timing results

**Given** the physics model section
**When** it is read
**Then** it states the simplification of rotating gravity only, without centrifugal, Coriolis or moving-wall effects (FR8b)

**Given** the report
**When** checked against the PRD success criteria
**Then** each criterion is addressed with evidence (waveforms, utilisation tables, demo result)
