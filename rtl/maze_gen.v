`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// maze_gen: deterministic connected-maze generator (Stories 1.3 and 7.5).
//
// Iterative recursive-backtracker (depth-first search) with an explicit stack.
// After the search, a loop pass may open up to K more interior walls, at most
// one per band of cell rows, so any loops spread from the goal side to the
// start side. The cap follows N, not the stage: N=10 gets 3, N=15 gets 5 and
// N=20 gets 6. Every other N, including EASY, stays a perfect maze.
//
// Loop pass: band k covers cell rows 3k..3k+2, and the last band also takes
// any rows left over (N=10: 0-2, 3-5, 6-9; N=15: five bands of 3; N=20: five
// bands of 3 and 15-19). From a
// seeded starting wall, it scans the band's interior walls (east, then south,
// row by row, wrapping) and opens the first one that is still closed. A band
// of R rows always has one: it has R(N-1)+(R-1)N interior walls, and the tree
// opens at most RN-1 of them, leaving at least (R-1)(N-1). A K set on another
// N must keep 3K <= N.
//
// The active tile map is (2N+1) x (2N+1), stored at addr={row, col} (a fixed
// 64-tile row on every stage, so no address needs a multiply).
// Cell (cx,cy) is tile (2*cx+1,2*cy+1); passages occupy the intervening tiles.
// Start is (2N-1,2N-1), goal is (1,1), and N is clamped to 2..20.
//
// Item boxes: EASY (N=5) has none, HARD keeps two buffs and two debuffs, and
// N >= 15 has three of each. Other eligible sizes retain four boxes.
// Positions are seeded within quadrants and avoid the start, goal, and all
// previously placed boxes. With six boxes the last two slots reuse quadrants 0/1.
//
// N > 15 draws its loop column and box cells from wider random fields (a
// 10-cell quadrant needs offsets up to 9). N <= 15 keeps the original fields,
// so its mazes and boxes are unchanged for every seed (tb_maze_gen_golden).
//
// Interface (contract v1.0):
//   gen_start (pulse) + n_cells + seed -> gen_busy ... gen_done (pulse).
//   Writes go out on we/waddr/wdata (maze_ram write port; this module is its
//   only writer, AD-5). start_*/goal_* hold the tile coordinates and stay
//   valid until the next generation. box_cols/box_rows hold box k's tile
//   coordinates at bits [COORD_W*k +: COORD_W], valid while box_valid[k] is set (cleared
//   when a generation starts).
// Randomness: xorshift32 (a 32-bit linear-feedback generator). The same seed
// always gives the same maze (NFR5); a zero seed is replaced by 1.
module maze_gen (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      gen_start,
    input  wire [`N_CELLS_W-1:0]     n_cells,
    input  wire [31:0]               seed,
    output reg                       gen_busy,
    output reg                       gen_done,
    output wire                      we,
    output wire [`MAP_ADDR_W-1:0]    waddr,
    output wire                      wdata,
    output reg  [`COORD_W-1:0]       start_col,
    output reg  [`COORD_W-1:0]       start_row,
    output reg  [`COORD_W-1:0]       goal_col,
    output reg  [`COORD_W-1:0]       goal_row,
    output reg  [6*`COORD_W-1:0]     box_cols,
    output reg  [6*`COORD_W-1:0]     box_rows,
    output reg  [5:0]                box_valid
);

    localparam [3:0] S_IDLE   = 4'd0,
                     S_CLEAR  = 4'd1,
                     S_INIT   = 4'd2,
                     S_STEP   = 4'd3,
                     S_PICK   = 4'd4,
                     S_WPASS  = 4'd5,
                     S_WCELL  = 4'd6,
                     S_FINISH = 4'd7,
                     S_BAND   = 4'd8,
                     S_SCAN   = 4'd9,
                     S_WLOOP  = 4'd10,
                     S_BOXES  = 4'd11,
                     S_BOX    = 4'd12;

    reg [3:0]  state;
    reg [4:0]  n;                 // maze size in cells (2..20)
    reg [31:0] rng;
    reg [3:0]  loop_cap;
    reg [3:0]  band_index;
    reg [`MAP_ADDR_W-1:0] clr_addr;
    reg [4:0]  cx, cy;            // current cell (top of the stack)
    reg [1:0]  dir;               // 0 = up, 1 = right, 2 = down, 3 = left
    // Cell records indexed {cy, cx}, all LUT RAM: cleared during S_CLEAR (which
    // walks 4096 map tiles, more than the 1024 entries), then set as below.
    reg        visited [0:1023];  // set in S_INIT (cell 0) and S_WCELL
    reg        open_e [0:1023];   // passage to the east / south cell is open
    reg        open_s [0:1023];   // (set in S_WPASS)
    reg [9:0]  stack [0:399];     // {cy, cx} per entry; 400 entries at N=20
    reg [8:0]  sp;                // number of entries on the stack (0..400)
    reg [4:0]  scx, scy;          // loop-pass scan position (cell)
    reg        sdir;              // 0 = east wall, 1 = south wall
    reg [2:0]  box_k;             // box being placed
    reg [2:0]  box_target;        // 0 up to N = 5, 4 standard, 6 from N = 15 up
    reg [1:0]  box_rot;           // quadrant of box 0
    reg        box_swap;          // swap the quadrants of boxes 1 and 2

    function [31:0] xorshift;
        input [31:0] x;
        reg [31:0] a, b;
        begin
            a = x ^ (x << 13);
            b = a ^ (a >> 17);
            xorshift = b ^ (b << 5);
        end
    endfunction

    // ---- unvisited-neighbour mask of the current cell ----
    wire [4:0] nm1 = n - 5'd1;
    wire avail_up    = (cy != 5'd0) && !visited[{cy - 5'd1, cx}];
    wire avail_right = (cx <  nm1)  && !visited[{cy, cx + 5'd1}];
    wire avail_down  = (cy <  nm1)  && !visited[{cy + 5'd1, cx}];
    wire avail_left  = (cx != 5'd0) && !visited[{cy, cx - 5'd1}];
    wire [3:0] avail = {avail_left, avail_down, avail_right, avail_up};

    // ---- next cell for the chosen direction ----
    wire [4:0] nx = (dir == 2'd1) ? cx + 5'd1 : (dir == 2'd3) ? cx - 5'd1 : cx;
    wire [4:0] ny = (dir == 2'd2) ? cy + 5'd1 : (dir == 2'd0) ? cy - 5'd1 : cy;

    // ---- tile coordinates (6 bits) ----
    wire [`COORD_W-1:0] cell_col  = {cx, 1'b1};
    wire [`COORD_W-1:0] cell_row  = {cy, 1'b1};
    wire [`COORD_W-1:0] pass_col  = (dir == 2'd1) ? cell_col + 1'b1 : (dir == 2'd3) ? cell_col - 1'b1 : cell_col;
    wire [`COORD_W-1:0] pass_row  = (dir == 2'd2) ? cell_row + 1'b1 : (dir == 2'd0) ? cell_row - 1'b1 : cell_row;
    wire [`COORD_W-1:0] next_col  = {nx, 1'b1};
    wire [`COORD_W-1:0] next_row  = {ny, 1'b1};

    // ---- loop pass: current band and scan candidate ----
    wire       wide      = (n > 5'd15);                              // N > 15 random fields
    wire [4:0] band_lo   = {1'b0, band_index[2:0], 1'b0} + {1'b0, band_index};   // 3k
    wire [4:0] band_hi   = (band_index == loop_cap - 4'd1) ? nm1 : band_lo + 5'd2;
    wire [4:0] band_span = band_hi - band_lo;                         // rows - 1
    wire [4:0] rand_src  = wide ? rng[4:0] : {1'b0, rng[3:0]};
    wire [4:0] rand_col  = (rand_src >= n) ? rand_src - n : rand_src;
    wire [4:0] rand_row  = ({3'b000, rng[9:8]} > band_span) ? 5'd0 : {3'b000, rng[9:8]};
    wire       scan_closed = sdir ? ((scy != band_hi) && !open_s[{scy, scx}])
                                  : ((scx != nm1)     && !open_e[{scy, scx}]);
    wire [`COORD_W-1:0] loop_col  = {scx, 1'b1} + {{(`COORD_W-1){1'b0}}, ~sdir};
    wire [`COORD_W-1:0] loop_row  = {scy, 1'b1} + {{(`COORD_W-1){1'b0}},  sdir};

    // ---- item boxes: quadrant of box k and a seeded cell inside it ----
    wire [4:0] half      = {1'b0, n[4:1]};
    wire [1:0] box_perm  = !box_swap       ? box_k[1:0] :
                           (box_k[1:0] == 2'd1) ? 2'd2  :
                           (box_k[1:0] == 2'd2) ? 2'd1  : box_k[1:0];
    wire [1:0] box_quad  = box_rot + box_perm;
    wire       quad_right = (box_quad == 2'd1) || (box_quad == 2'd2);
    wire       quad_low   = box_quad[1];
    // A 10-cell quadrant (N=20) needs offsets 0..9; N <= 15 keeps 0..7.
    wire [4:0] box_xoff  = wide ? {1'b0, rng[3:0]} : {2'b00, rng[2:0]};
    wire [4:0] box_yoff  = wide ? {1'b0, rng[7:4]} : {2'b00, rng[6:4]};
    wire [4:0] box_cx    = (quad_right ? half : 5'd0) + box_xoff;
    wire [4:0] box_cy    = (quad_low   ? half : 5'd0) + box_yoff;
    reg        box_duplicate;
    integer    box_check_index;
    always @* begin
        box_duplicate = 1'b0;
        for (box_check_index = 0; box_check_index < 6; box_check_index = box_check_index + 1)
            if (box_valid[box_check_index] &&
                box_cols[box_check_index * `COORD_W +: `COORD_W] == {box_cx, 1'b1} &&
                box_rows[box_check_index * `COORD_W +: `COORD_W] == {box_cy, 1'b1})
                box_duplicate = 1'b1;
    end
    wire       box_ok    = (box_xoff < (quad_right ? n - half : half)) &&
                           (box_yoff < (quad_low   ? n - half : half)) &&
                           ({box_cy, box_cx} != {nm1, nm1}) &&      // start cell
                           ({box_cy, box_cx} != 10'd0) &&            // goal cell
                           !box_duplicate;

    // ---- open-passage record: one write per cycle, no reset ----
    wire       open_clr  = (state == S_CLEAR);
    wire       open_we_e = open_clr || ((state == S_WPASS) && dir[0]);    // right / left
    wire       open_we_s = open_clr || ((state == S_WPASS) && !dir[0]);   // up / down
    wire [9:0] open_wa_e = open_clr ? clr_addr[9:0] : (dir == 2'd1) ? {cy, cx} : {ny, nx};
    wire [9:0] open_wa_s = open_clr ? clr_addr[9:0] : (dir == 2'd2) ? {cy, cx} : {ny, nx};
    // visited: one write port; the four neighbour reads above are async.
    wire       vis_we    = open_clr || (state == S_INIT) || (state == S_WCELL);
    wire [9:0] vis_wa    = open_clr ? clr_addr[9:0] : (state == S_INIT) ? 10'd0 : {ny, nx};
    always @(posedge clk) begin
        if (open_we_e) open_e[open_wa_e] <= !open_clr;
        if (open_we_s) open_s[open_wa_s] <= !open_clr;
        if (vis_we)    visited[vis_wa]   <= !open_clr;
    end

    // ---- map write port (combinational from state, registered state) ----
    // The whole 64x64 store is cleared to wall, so every stage starts clean.
    assign we    = (state == S_CLEAR) || (state == S_INIT) ||
                   (state == S_WPASS) || (state == S_WCELL) ||
                   (state == S_WLOOP);
    assign wdata = (state == S_CLEAR);   // wall while clearing, floor otherwise
    assign waddr = (state == S_CLEAR) ? clr_addr :
                   (state == S_INIT)  ? {{(`COORD_W-1){1'b0}}, 1'b1, {(`COORD_W-1){1'b0}}, 1'b1} :
                   (state == S_WPASS) ? {pass_row, pass_col} :
                   (state == S_WLOOP) ? {loop_row, loop_col} :
                                        {next_row, next_col};

    always @(posedge clk) begin
        gen_done <= 1'b0;
        if (rst) begin
            state    <= S_IDLE;
            gen_busy <= 1'b0;
            gen_done <= 1'b0;
            sp       <= 9'd0;
            box_valid <= 6'b000000;
            box_cols  <= {6*`COORD_W{1'b0}};
            box_rows  <= {6*`COORD_W{1'b0}};
            box_target <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (gen_start) begin
                        n        <= (n_cells < 2) ? 5'd2 :
                                    (n_cells > `MAX_N_CELLS) ? `MAX_N_CELLS : n_cells;
                        rng      <= (seed == 32'd0) ? 32'd1 : seed;
                        clr_addr <= {`MAP_ADDR_W{1'b0}};
                        gen_busy <= 1'b1;
                        box_valid <= 6'b000000;
                        box_cols  <= {6*`COORD_W{1'b0}};
                        box_rows  <= {6*`COORD_W{1'b0}};
                        state    <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    if (clr_addr == `MAP_TILES - 1) state <= S_INIT;
                    else                            clr_addr <= clr_addr + 1'b1;
                end

                S_INIT: begin
                    // visited[0] (cell (0,0)) is written by the port above.
                    stack[0]         <= 10'd0;
                    sp               <= 9'd1;
                    cx               <= 5'd0;
                    cy               <= 5'd0;
                    start_col        <= {nm1, 1'b1};
                    start_row        <= {nm1, 1'b1};
                    goal_col         <= {{(`COORD_W-1){1'b0}}, 1'b1};
                    goal_row         <= {{(`COORD_W-1){1'b0}}, 1'b1};
                    // One loop per 3-row band from N = 8 up (3/5/6 at
                    // N = 10/15/20); below 8, rand_col could pass nm1.
                    loop_cap         <= (n < 5'd8) ? 4'd0 : n / 5'd3;
                    // No boxes up to N = 5 (EASY), 4 below N = 15, then 6.
                    box_target       <= (n <= 5'd5) ? 3'd0 :
                                        (n >= 5'd15) ? 3'd6 : 3'd4;
                    band_index       <= 4'd0;
                    state            <= S_STEP;
                end

                S_STEP: begin
                    if (avail != 4'b0000) begin
                        state <= S_PICK;
                    end else if (sp <= 9'd1) begin         // stack exhausted
                        state <= (loop_cap != 4'd0) ? S_BAND : S_BOXES;
                    end else begin
                        sp <= sp - 9'd1;                    // backtrack
                        {cy, cx} <= stack[sp - 9'd2];
                    end
                end

                S_PICK: begin
                    rng <= xorshift(rng);
                    if (avail[rng[17:16]]) begin            // reject unavailable directions
                        dir   <= rng[17:16];
                        state <= S_WPASS;
                    end
                end

                S_WPASS: state <= S_WCELL;                  // also records the passage

                S_WCELL: begin
                    // visited[{ny, nx}] is written by the port above.
                    stack[sp]         <= {ny, nx};
                    sp                <= sp + 9'd1;
                    cx                <= nx;
                    cy                <= ny;
                    state             <= S_STEP;
                end

                S_BAND: begin                               // seeded optional loop in band k
                    rng   <= xorshift(rng);
                    // One seeded bit skips or selects this band; either way,
                    // the next band remains in the same goal-to-start order.
                    if (rng[31]) begin
                        scx   <= rand_col;
                        scy   <= band_lo + rand_row;
                        sdir  <= rng[12];
                        state <= S_SCAN;
                    end else if (band_index == loop_cap - 4'd1) begin
                        state <= S_BOXES;
                    end else begin
                        band_index <= band_index + 4'd1;
                    end
                end

                S_SCAN: begin
                    if (scan_closed) begin
                        state <= S_WLOOP;
                    end else if (!sdir) begin
                        sdir <= 1'b1;
                    end else begin
                        sdir <= 1'b0;
                        if (scx == nm1) begin
                            scx <= 5'd0;
                            scy <= (scy == band_hi) ? band_lo : scy + 5'd1;
                        end else begin
                            scx <= scx + 5'd1;
                        end
                    end
                end

                S_WLOOP: begin                              // write port opens the wall
                    if (band_index == loop_cap - 4'd1) begin
                        state <= S_BOXES;
                    end else begin
                        band_index <= band_index + 4'd1;
                        state      <= S_BAND;
                    end
                end

                S_BOXES: begin                              // seeded quadrant order
                    rng      <= xorshift(rng);
                    box_rot  <= rng[1:0];
                    box_swap <= rng[2];
                    box_k    <= 3'd0;
                    state    <= (box_target == 3'd0) ? S_FINISH : S_BOX;
                end

                S_BOX: begin                                // reject cells outside the quadrant
                    rng <= xorshift(rng);
                    if (box_ok) begin
                        box_cols[box_k * `COORD_W +: `COORD_W] <= {box_cx, 1'b1};
                        box_rows[box_k * `COORD_W +: `COORD_W] <= {box_cy, 1'b1};
                        box_valid[box_k] <= 1'b1;
                        box_k            <= box_k + 3'd1;
                        if (box_k == box_target - 3'd1) state <= S_FINISH;
                    end
                end

                S_FINISH: begin
                    gen_done <= 1'b1;
                    gen_busy <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
