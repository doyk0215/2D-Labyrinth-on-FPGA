`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Explosion visual of the WALL BREAKER buff. It runs in maze space around the
// blast's centre tile: a bright flash over the 5 x 5 block, a shockwave ring
// that grows from radius 1 to 2, then dim embers. render turns these fields
// into a colour tint on the wall and floor tiles, so the picture turns and
// scrolls with the maze and always covers exactly the tiles that were cleared.
//
// The state changes only when a blast starts (physics completion, in vertical
// blanking) or on frame_tick, so every field is steady for a whole visible
// frame. PAUSED freezes the animation in place; any other non-PLAY state, a
// new maze or a reset cancels it.
module blast_effect #(
    parameter integer STEP_FRAMES = 3      // frames per animation step
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         phys_init,
    input  wire                         frame_tick,
    input  wire [`GAME_STATE_W-1:0]     game_state,
    input  wire                         start,        // wall_breaker.blast_start
    input  wire [`COORD_W-1:0]          centre_col,
    input  wire [`COORD_W-1:0]          centre_row,
    output reg                          on = 1'b0,
    output reg  [`COORD_W-1:0]          col = {`COORD_W{1'b0}},
    output reg  [`COORD_W-1:0]          row = {`COORD_W{1'b0}},
    output wire                         fill,         // 1: every tile within radius, 0: only the ring
    output wire [1:0]                   radius,       // Chebyshev distance in tiles, 0..2
    output wire [11:0]                  rgb           // tint, RGB444
);
    localparam integer STEPS = 6;
    localparam integer CNT_W = (STEP_FRAMES > 1) ? $clog2(STEP_FRAMES) : 1;

    reg [2:0] step = 3'd0;
    reg [CNT_W-1:0] cnt = {CNT_W{1'b0}};

    wire keep_state = (game_state == `ST_PLAY) || (game_state == `ST_PAUSED);

    always @(posedge clk) begin
        if (rst || phys_init || !keep_state) begin
            on <= 1'b0;
            step <= 3'd0;
            cnt <= {CNT_W{1'b0}};
        end else if (start) begin
            on <= 1'b1;                          // a new blast restarts the animation
            step <= 3'd0;
            cnt <= {CNT_W{1'b0}};
            col <= centre_col;
            row <= centre_row;
        end else if (on && frame_tick && game_state == `ST_PLAY) begin
            if (cnt == STEP_FRAMES - 1) begin
                cnt <= {CNT_W{1'b0}};
                if (step == STEPS - 1) on <= 1'b0;
                else step <= step + 1'b1;
            end else cnt <= cnt + 1'b1;
        end
    end

    // flash, flash, ring 1, ring 2, embers, fading embers
    reg        fill_r;
    reg [1:0]  radius_r;
    reg [11:0] rgb_r;
    always @* begin
        case (step)
            3'd0:    begin fill_r = 1'b1; radius_r = 2'd2; rgb_r = 12'hffe; end
            3'd1:    begin fill_r = 1'b1; radius_r = 2'd2; rgb_r = 12'hfc4; end
            3'd2:    begin fill_r = 1'b0; radius_r = 2'd1; rgb_r = 12'hf82; end
            3'd3:    begin fill_r = 1'b0; radius_r = 2'd2; rgb_r = 12'hf62; end
            3'd4:    begin fill_r = 1'b1; radius_r = 2'd2; rgb_r = 12'ha30; end
            default: begin fill_r = 1'b1; radius_r = 2'd2; rgb_r = 12'h520; end
        endcase
    end
    assign fill = fill_r;
    assign radius = radius_r;
    assign rgb = rgb_r;
endmodule
