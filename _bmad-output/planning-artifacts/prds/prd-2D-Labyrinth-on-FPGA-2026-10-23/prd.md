---
title: 2D Labyrinth on FPGA
status: final
created: 2026-10-23
updated: 2026-10-23
---

# 2D Labyrinth on FPGA — PRD

Items tagged `[ASSUMPTION]` were inferred and need confirmation.

## 1. Summary

A handheld-style tilt-maze game implemented in hardware on an FPGA. A small ball sits in a randomly generated maze. The player rotates the whole maze with the mouse; gravity always points down on screen, so rotating the maze steers the ball toward the goal. Stakes: a graded university project, so the PRD optimises for a demonstrable, verifiable design that fits the course timeline.

## 2. Goals and non-goals

**Goals**
- A playable game on a real board: a randomly generated maze, a ball obeying simple physics, and a visible goal.
- Holding the left or right mouse button to turn the maze is the only gameplay input.
- Physics are deterministic and visibly "right": constant downward gravity, slightly bouncy wall collisions, no friction.
- Each design block can be simulated and explained in the course report and demo.

**Non-goals** `[ASSUMPTION]`
- Sound, multiplayer, high-score persistence and a soft-CPU or OS. Menus are in scope, but only on the OLED (see FR-20 to FR-24).

## 3. Target platform `[ASSUMPTION]`

- Digilent Basys 3 (Artix-7), confirmed. Its USB-HID host port exposes a PS/2 mouse. `[ASSUMPTION]` for the mouse path.
- Verilog, built in Vivado, confirmed.
- Output: the Basys 3 VGA port feeds an external VGA-to-HDMI converter, which drives an HDMI monitor. The FPGA design only produces standard analog VGA 640×480 @ 60 Hz (12-bit colour, HSYNC and VSYNC); no HDMI logic is needed on the FPGA. `[ASSUMPTION]` for the resolution; confirm the converter accepts 640×480.
- Secondary display: an OLED module on the board (Digilent Pmod OLED on a Pmod header, SPI, confirmed). The Basys 3 has no built-in OLED, so this is an external module.
- Input: mouse left and right buttons. The board's buttons or switches drive the OLED menu `[ASSUMPTION]`. Optional extras: a reset button, a seven-segment display for the timer, LEDs for status.

## 4. Primary user journey

Sam, a course examiner, powers on the board. A maze appears with the ball at the start and a goal marker at the far side. Sam holds the right button and the maze turns clockwise; the ball, pulled down by gravity, rolls and bounces off a wall. After a few more turns the ball reaches the goal. The game shows a win state, and after a short pause (or a reset press) a new, different random maze appears.

## 5. Functional requirements

### Maze
- **FR-1** The system generates a new random maze on power-up and after each win.
- **FR-2** Every generated maze is solvable from the start to the goal. `[ASSUMPTION]` A perfect-maze algorithm (for example DFS or randomised Prim) on a grid guarantees this.
- **FR-3** Randomness comes from a hardware PRNG (such as an LFSR) seeded from a source that varies between runs, for example a free-running counter sampled at the first mouse click. `[ASSUMPTION]`
- **FR-4** The start cell and goal cell are visually distinct from each other and from the maze.

### Rotation
- **FR-5** While the left mouse button is held, the maze rotates counter-clockwise at a constant angular speed; while the right button is held, it rotates clockwise. `[ASSUMPTION]` Speed is about 90° per second; tune by feel.
- **FR-6** Releasing the button stops the rotation immediately and the maze holds its angle. `[ASSUMPTION]` Holding both buttons, or neither, means no rotation.
- **FR-7** The angle is continuous and unbounded (it wraps at 360°). The maze is drawn at its exact current angle on every frame, using a sine/cosine lookup table in hardware.
- **FR-8** Gravity always points down on screen. In the maze's own frame, gravity therefore rotates with the opposite angle, and the ball feels it on every frame, including mid-rotation.
- **FR-8b** `[ASSUMPTION]` For simplicity, physics runs in the maze frame and models only the rotating gravity. Frame effects such as the centrifugal and Coriolis forces and moving-wall impacts are ignored; the course report states this simplification.

### Ball physics
- **FR-9** Gravity is constant and points down on screen at all times.
- **FR-10** The ball moves in continuous (fixed-point) position and velocity, updated once per frame.
- **FR-11** On collision with a wall, the ball's velocity component normal to the wall reverses and is scaled by a restitution coefficient below 1 (a "bit elastic", for example around 0.5–0.7). `[ASSUMPTION]`
- **FR-12** There is no friction: tangential velocity is unchanged by collisions and no drag is applied.
- **FR-13** The ball never passes through or gets stuck inside a wall at any speed the physics can produce (a speed cap may be applied).
- **FR-14** When the maze rotates, the ball keeps its position relative to the maze and is affected by the effective gravity direction at every frame (see FR-8). Physics and collisions run in the maze's own frame, so walls stay axis-aligned for collision tests.

### Game flow
- **FR-15** Reaching the goal cell triggers a win state, then a fresh random maze.
- **FR-16** A reset button restores the initial state and generates a new maze.
- **FR-17** A timer shows elapsed time for the current maze on the seven-segment display or on screen. `[ASSUMPTION]` Optional.

### Display split
- **FR-20** The VGA/HDMI monitor shows the maze itself: the maze, ball, start, goal and win state. It shows no menus.
- **FR-21** The OLED module handles the menu, stage selection and settings, and is the only place they appear.

### OLED menu, stages and settings `[ASSUMPTION]` for all details below
- **FR-22** On power-up the OLED shows a menu. Using the board's buttons, the player selects a stage and starts the game.
- **FR-23** A stage defines a maze difficulty, for example grid size and/or restitution. The OLED lists the stages and shows the selected one.
- **FR-24** The OLED settings screen lets the player adjust at least the rotation speed (and optionally restitution). Changes apply to the next game.
- **FR-25** During play the OLED shows live status such as the stage number and the elapsed time (this replaces the timer in FR-17 if the OLED is available).
- **FR-26** The game starts only after a stage is chosen on the OLED, and a reset returns to the menu.

### Display and input
- **FR-18** The display shows the maze, ball, start and goal at 60 frames per second without tearing.
- **FR-19** The mouse is read through a PS/2 receiver; only the left and right button states are used.

## 6. Non-functional requirements

- **NFR-1** Timing closure at the 100 MHz board clock and the 25 MHz pixel clock with no failing paths.
- **NFR-1b** The VGA signal is compatible with the VGA-to-HDMI converter (standard 640×480 @ 60 Hz timing) so the monitor locks without manual setup. `[ASSUMPTION]`
- **NFR-2** Physics update completes within one frame so the game never stutters.
- **NFR-3** The design fits the board's logic and block-RAM resources with at least 20% headroom. `[ASSUMPTION]`
- **NFR-4** Modular design, with separate blocks for mouse input, maze generation, rotation, physics, rendering, display timing, OLED driver and menu control, each with a simulation testbench.
- **NFR-5** The behaviour is reproducible: the same PRNG seed gives the same maze, for debugging.

## 7. Success criteria (for grading)

- Live demo: the maze is generated, rotated by holding the mouse buttons, and the ball is solved to the goal at least three times with different mazes.
- Testbench waveforms show: maze solvability, collision response with restitution, and no tunnelling through walls.
- A report explains the architecture, the physics model and the resource and timing results.
- Counter-check: the game must not trade away verifiability for visual polish. A simpler working design beats a fancy unfinished one.

## 8. Schedule and scope (3 weeks) `[ASSUMPTION]`

The project is due in 3 weeks. Smooth rotation is the riskiest part, so build in stages, each demonstrable on its own:
1. **Week 1:** VGA output, PS/2 mouse input, static maze generation and drawing, with testbenches. Bring up the OLED (SPI) with a fixed text screen in parallel.
2. **Week 2:** ball physics (gravity, elastic bounce, no friction) and goal detection, with a fixed 90° rotation step as the fallback.
3. **Week 3:** smooth rotation rendering and gravity, OLED menu with stage selection and settings, integration, timing closure, demo and report.

If time runs short, ship the stage-2 build (snap rotation) as the fallback and document smooth rotation as partial.

## 9. Open questions

1. Does the course impose any further constraint on the design (for example no IP cores, or a required deliverable)? Board, HDL and toolchain are settled: Basys 3, Verilog, Vivado.
2. Does the course require a particular grading deliverable such as a report, a presentation or a lab demo date?
3. Is the physics simplification in FR-8b acceptable to the course (rotating gravity only, no fictitious forces)?
4. How is the OLED menu navigated (board buttons or switches), and what exactly do stages and settings change?
5. Maze grid size: for example 16×12 cells at 40 px on VGA 640×480. `[ASSUMPTION]`
