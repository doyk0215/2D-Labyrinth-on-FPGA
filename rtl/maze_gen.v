`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// maze_gen: random perfect-maze generator (Story 1.3, AD-12).
//
// Iterative recursive-backtracker (depth-first search) with an explicit stack.
// A perfect maze has exactly one path between any two cells, so the start and
// goal are always connected (FR2).
//
// The active tile map is (2N+1) x (2N+1), packed at addr=row*(2N+1)+col.
// Cell (cx,cy) is tile (2*cx+1,2*cy+1); passages occupy the intervening tiles.
// Start is (2N-1,2N-1), goal is (1,1), and N is clamped to 2..15.
//
// Interface (contract v1.0):
//   gen_start (pulse) + n_cells + seed -> gen_busy ... gen_done (pulse).
//   Writes go out on we/waddr/wdata (maze_ram write port; this module is its
//   only writer, AD-5). start_*/goal_* hold the tile coordinates and stay
//   valid until the next generation.
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
    output reg  [`COORD_W-1:0]       goal_row
);

    localparam [3:0] S_IDLE   = 4'd0,
                     S_CLEAR  = 4'd1,
                     S_INIT   = 4'd2,
                     S_STEP   = 4'd3,
                     S_PICK   = 4'd4,
                     S_WPASS  = 4'd5,
                     S_WCELL  = 4'd6,
                     S_FINISH = 4'd7;

    reg [3:0]  state;
    reg [3:0]  n;                 // maze size in cells (2..15)
    reg [31:0] rng;
    reg [9:0]  clr_addr;
    reg [3:0]  cx, cy;            // current cell (top of the stack)
    reg [1:0]  dir;               // 0 = up, 1 = right, 2 = down, 3 = left
    reg [255:0] visited;          // indexed {cy, cx}
    reg [7:0]  stack [0:224];     // {cy, cx} per entry; 225 entries at N=15
    reg [7:0]  sp;                // number of entries on the stack (0..225)

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
    wire [3:0] nm1 = n - 4'd1;
    wire avail_up    = (cy != 4'd0) && !visited[{cy - 4'd1, cx}];
    wire avail_right = (cx <  nm1)  && !visited[{cy, cx + 4'd1}];
    wire avail_down  = (cy <  nm1)  && !visited[{cy + 4'd1, cx}];
    wire avail_left  = (cx != 4'd0) && !visited[{cy, cx - 4'd1}];
    wire [3:0] avail = {avail_left, avail_down, avail_right, avail_up};

    // ---- next cell for the chosen direction ----
    wire [3:0] nx = (dir == 2'd1) ? cx + 4'd1 : (dir == 2'd3) ? cx - 4'd1 : cx;
    wire [3:0] ny = (dir == 2'd2) ? cy + 4'd1 : (dir == 2'd0) ? cy - 4'd1 : cy;

    // ---- tile coordinates (5 bits) ----
    wire [4:0] cell_col  = {cx, 1'b1};
    wire [4:0] cell_row  = {cy, 1'b1};
    wire [4:0] pass_col  = (dir == 2'd1) ? cell_col + 5'd1 : (dir == 2'd3) ? cell_col - 5'd1 : cell_col;
    wire [4:0] pass_row  = (dir == 2'd2) ? cell_row + 5'd1 : (dir == 2'd0) ? cell_row - 5'd1 : cell_row;
    wire [4:0] next_col  = {nx, 1'b1};
    wire [4:0] next_row  = {ny, 1'b1};

    // row * (2*N+1) + col; each stage occupies a packed RAM prefix.
    function [`MAP_ADDR_W-1:0] tile_addr;
        input [4:0] col;
        input [4:0] row;
        input [3:0] maze_n;
        reg [9:0] dim;
        begin
            dim = ({6'd0, maze_n} << 1) + 10'd1;
            tile_addr = row * dim + col;
        end
    endfunction

    // ---- map write port (combinational from state, registered state) ----
    assign we    = (state == S_CLEAR) || (state == S_INIT) ||
                   (state == S_WPASS) || (state == S_WCELL);
    assign wdata = (state == S_CLEAR);   // wall while clearing, floor otherwise
    assign waddr = (state == S_CLEAR) ? clr_addr :
                   (state == S_INIT)  ? tile_addr(5'd1, 5'd1, n) :
                   (state == S_WPASS) ? tile_addr(pass_col, pass_row, n) :
                                        tile_addr(next_col, next_row, n);

    always @(posedge clk) begin
        gen_done <= 1'b0;
        if (rst) begin
            state    <= S_IDLE;
            gen_busy <= 1'b0;
            gen_done <= 1'b0;
            sp       <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (gen_start) begin
                        n        <= (n_cells < 4'd2) ? 4'd2 : n_cells;
                        rng      <= (seed == 32'd0) ? 32'd1 : seed;
                        clr_addr <= 10'd0;
                        gen_busy <= 1'b1;
                        state    <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    if (clr_addr == `MAP_TILES - 1) state <= S_INIT;
                    else                            clr_addr <= clr_addr + 10'd1;
                end

                S_INIT: begin
                    visited          <= 256'd0;
                    visited[8'd0]    <= 1'b1;        // cell (0,0)
                    stack[0]         <= 8'd0;
                    sp               <= 8'd1;
                    cx               <= 4'd0;
                    cy               <= 4'd0;
                    start_col        <= {n - 4'd1, 1'b1};
                    start_row        <= {n - 4'd1, 1'b1};
                    goal_col         <= 5'd1;
                    goal_row         <= 5'd1;
                    state            <= S_STEP;
                end

                S_STEP: begin
                    if (avail != 4'b0000) begin
                        state <= S_PICK;
                    end else if (sp <= 8'd1) begin
                        state <= S_FINISH;                 // stack exhausted
                    end else begin
                        sp <= sp - 8'd1;                    // backtrack
                        {cy, cx} <= stack[sp - 8'd2];
                    end
                end

                S_PICK: begin
                    rng <= xorshift(rng);
                    if (avail[rng[17:16]]) begin            // reject unavailable directions
                        dir   <= rng[17:16];
                        state <= S_WPASS;
                    end
                end

                S_WPASS: state <= S_WCELL;

                S_WCELL: begin
                    visited[{ny, nx}] <= 1'b1;
                    stack[sp]         <= {ny, nx};
                    sp                <= sp + 8'd1;
                    cx                <= nx;
                    cy                <= ny;
                    state             <= S_STEP;
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
