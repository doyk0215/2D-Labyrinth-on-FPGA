// labyrinth_pkg.vh -- shared constants for the 2D Labyrinth on FPGA design.
// Owner: DY. Changes need approval from DY, QZ and CJX (see docs/parallel-workstreams.md).
// Source: architecture spine AD-4 and the interface contract v1.0.
// Usage in every module:  `include "labyrinth_pkg.vh"
`ifndef LABYRINTH_PKG_VH
`define LABYRINTH_PKG_VH

// ---- Angle: unsigned, 4096 steps = 360 degrees ----
`define ANGLE_W        12

// ---- Trig (sin_q, cos_q): signed Q1.14 ----
`define TRIG_W         16
`define TRIG_FRAC      14
`define SINCOS_TBL_N   256      // quarter-wave table entries

// ---- Ball position: signed Q9.8, maze pixels from the maze centre ----
`define POS_W          18
`define POS_FRAC       8

// ---- Ball velocity: signed Q4.8, pixels per frame ----
`define VEL_W          12
`define VEL_FRAC       8
`define VEL_CAP        1280     // 5 px/frame * 256 (max representable is 7.996)
`define GRAVITY_Q14    2458     // round(0.15 * 2^14); average acceleration in px/frame^2
`define GRAVITY_FRAC   20       // product Q2.28 -> velocity Q4.8 with carried fraction bits

// ---- Maze geometry ----
`define TILE_PX        16       // pixels per tile
`define TILE_SHIFT     12       // log2(TILE_PX) + POS_FRAC: Q9.8 maze pixels >> 12 = tile index
`define MAP_DIM        21       // tile map is 21 x 21 (10 cells + walls)
`define MAP_TILES      441      // 21 * 21
`define MAP_ADDR_W     9        // addr = row * 21 + col
`define MAP_MID        10       // centre tile index; an N-cell maze fills tiles (10-N)..(10+N)
`define COORD_W        5        // tile column / row index width
`define N_CELLS_W      4        // maze size in cells (up to 10)
`define BALL_RADIUS    5        // pixels

// ---- Screen: VGA 640x480 @ 60 Hz, 25 MHz pixel enable ----
`define H_VISIBLE      640
`define V_VISIBLE      480
`define H_TOTAL        800
`define V_TOTAL        525
`define SCREEN_CX      320      // maze rotation centre on screen
`define SCREEN_CY      240

// ---- Shared game state (Story 6.1) ----
// Keep v1's codes; ST_LOSE is reserved for Story 8.2 and is not entered yet.
`define GAME_STATE_W   3
`define ST_MENU        3'd0
`define ST_GENERATE    3'd1
`define ST_PLAY        3'd2
`define ST_WIN         3'd3
`define ST_LOSE        3'd4

// ---- Rotation command (rot_cmd[1:0], signed) ----
`define ROT_CCW        2'b11    // -1
`define ROT_NONE       2'b00    //  0
`define ROT_CW         2'b01    // +1

// ---- Game configuration (game_cfg) field widths ----
`define RESTIT_SEL_W   2        // 0 = 0.5 (EASY), 1 = 0.75 (HARD), 2 = 0.625, 3 = 0.375
`define ROT_SPEED_W    2

// ---- OLED text buffer: 4 rows x 16 columns, ASCII ----
`define OLED_ROWS      4
`define OLED_COLS      16
`define OLED_CHARS     64       // status_text is 64 * 8 = 512 bits

`endif
