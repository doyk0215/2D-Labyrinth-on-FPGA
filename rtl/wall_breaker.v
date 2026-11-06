`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Wall breaker: the bomb of the WALL BREAKER buff. A trigger waits for the
// next physics completion in PLAY (vertical blanking, so no visible frame is
// half edited and physics is idle), then clears every interior wall tile in a
// (2*BLAST_RADIUS+1)-square block centred on the ball's tile, one write per
// clock. The outer border (tile 0 and 2N) and everything past it are never
// written. maze_gen rewrites the whole map on the next generation, so broken
// walls last only until the maze is regenerated.
module wall_breaker #(
    parameter integer BLAST_RADIUS = 2
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         phys_init,
    input  wire [`GAME_STATE_W-1:0]     game_state,
    input  wire                         phys_done,
    input  wire                         trigger,
    input  wire [`N_CELLS_W-1:0]        n_cells,
    input  wire signed [`POS_W-1:0]     ball_x,
    input  wire signed [`POS_W-1:0]     ball_y,
    output reg                          we,
    output reg  [`MAP_ADDR_W-1:0]       waddr,
    output wire                         wdata,
    output wire                         busy
);
    localparam integer SIDE = 2 * BLAST_RADIUS + 1;
    localparam integer IDX_W = (SIDE > 1) ? $clog2(SIDE) : 1;

    assign wdata = 1'b0;                       // floor

    // Same stage-centred arithmetic as item_ctrl, with the sign extension that
    // keeps tiles near the negative map edge correct.
    wire signed [18:0] centre = ($signed({{(19-`N_CELLS_W){1'b0}}, n_cells}) <<< `TILE_SHIFT) + 19'sd2048;
    wire signed [18:0] absolute_x = $signed({ball_x[`POS_W-1], ball_x}) + centre;
    wire signed [18:0] absolute_y = $signed({ball_y[`POS_W-1], ball_y}) + centre;
    wire [`COORD_W-1:0] ball_col = absolute_x[`TILE_SHIFT+`COORD_W-1:`TILE_SHIFT];
    wire [`COORD_W-1:0] ball_row = absolute_y[`TILE_SHIFT+`COORD_W-1:`TILE_SHIFT];
    wire [`COORD_W-1:0] max_tile = {n_cells, 1'b0};
    wire in_map = !absolute_x[18] && !absolute_y[18] &&
                  ball_col <= max_tile && ball_row <= max_tile;

    reg pending = 1'b0;
    reg running = 1'b0;
    reg [`COORD_W-1:0] centre_col, centre_row;
    reg [`COORD_W-1:0] limit;                  // last interior tile index, 2N-1
    reg [IDX_W-1:0] ix, iy;
    assign busy = running;

    // The game may leave PLAY only through PAUSED (kept) or an end/restart
    // state (dropped).
    wire keep_state = (game_state == `ST_PLAY) || (game_state == `ST_PAUSED);
    wire in_play = (game_state == `ST_PLAY);

    // Signed tile of the current sweep step.
    wire signed [8:0] col_s = $signed({3'b000, centre_col}) + $signed({{(9-IDX_W){1'b0}}, ix}) - BLAST_RADIUS;
    wire signed [8:0] row_s = $signed({3'b000, centre_row}) + $signed({{(9-IDX_W){1'b0}}, iy}) - BLAST_RADIUS;
    wire interior = (col_s >= 9'sd1) && (row_s >= 9'sd1) &&
                    (col_s <= $signed({3'b000, limit})) && (row_s <= $signed({3'b000, limit}));

    always @(posedge clk) begin
        we <= 1'b0;
        if (rst || phys_init || !keep_state) begin
            pending <= 1'b0;
            running <= 1'b0;
            ix <= {IDX_W{1'b0}};
            iy <= {IDX_W{1'b0}};
        end else begin
            if (trigger) pending <= 1'b1;
            if (running) begin
                if (!in_play) begin
                    running <= 1'b0;            // never straddle a pause
                end else begin
                    if (interior) begin
                        we <= 1'b1;
                        waddr <= {row_s[`COORD_W-1:0], col_s[`COORD_W-1:0]};
                    end
                    if (ix == SIDE - 1) begin
                        ix <= {IDX_W{1'b0}};
                        if (iy == SIDE - 1) begin
                            iy <= {IDX_W{1'b0}};
                            running <= 1'b0;
                        end else iy <= iy + 1'b1;
                    end else ix <= ix + 1'b1;
                end
            end else if (in_play && phys_done && (pending || trigger) && in_map) begin
                pending <= 1'b0;
                running <= 1'b1;
                centre_col <= ball_col;
                centre_row <= ball_row;
                limit <= max_tile - 1'b1;
                ix <= {IDX_W{1'b0}};
                iy <= {IDX_W{1'b0}};
            end
        end
    end
endmodule
