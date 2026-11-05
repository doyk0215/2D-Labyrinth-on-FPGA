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
`define MAX_N_CELLS    20       // largest supported maze (N = 20, tested on its own)
`define MAP_DIM        41       // maximum active map side: 2*N + 1
`define MAP_STRIDE     64       // tiles per stored row on every stage: addr = {row, col}
`define MAP_TILES      4096     // storage: 64 rows x 64 columns (rows/columns 41..63 unused)
`define MAP_ADDR_W     12       // addr[11:6] = row, addr[5:0] = col
`define MAP_MID        20       // maximum map's centre tile index
`define COORD_W        6        // tile column / row index width (0..40)
`define N_CELLS_W      5        // maze size in cells (2..20)
`define BALL_RADIUS    5        // pixels

// ---- Screen: VGA 640x480 @ 60 Hz, 25 MHz pixel enable ----
`define H_VISIBLE      640
`define V_VISIBLE      480
`define H_TOTAL        800
`define V_TOTAL        525
`define SCREEN_CX      320      // maze rotation centre on screen
`define SCREEN_CY      240

// ---- Shared game state (Story 6.1) ----
// Keep v1's codes; LOSE marks countdown expiry and PAUSED freezes an active run.
`define GAME_STATE_W   3
`define ST_MENU        3'd0
`define ST_GENERATE    3'd1
`define ST_PLAY        3'd2
`define ST_WIN         3'd3
`define ST_LOSE        3'd4
`define ST_PAUSED      3'd5

// ---- Item effects (Story 9.2), IDs match item_icon_rom for 0..7 ----
`define ITEM_EFFECT_W  4
`define ITEM_LOW_GRAV  4'd0
`define ITEM_INVINCIBLE 4'd1
`define ITEM_TIME_BONUS 4'd2
`define ITEM_REVERSE_GRAV 4'd3
`define ITEM_HIGH_GRAV 4'd4
`define ITEM_ZERO_GRAV 4'd5
`define ITEM_INVERT    4'd6
`define ITEM_FOG       4'd7
// ID 8 is reserved for Kim's Wall Breaker buff. Existing IDs stay stable.
`define ITEM_INSTANT_DEATH 4'd9
`define ITEM_ICON_W    4
`define ITEM_VISUAL_W  5       // {icon-source enable, four-bit item/icon ID}
`define ITEM_NONE      4'd15

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
