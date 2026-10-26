`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// ball_overlay: where the ball appears on the screen, and a per-pixel "this
// pixel is ball" flag (Story 3.1).
//
// The ball position (maze coordinates from the map centre) is rotated into
// screen coordinates with the same angle render.v uses; render.v maps
// screen -> maze with a clockwise-positive angle, so maze -> screen is
//     sx = mx*cos - my*sin,   sy = mx*sin + my*cos
// (offsets from the screen centre). The result is computed once per frame,
// when `start` (ball_physics phys_done) pulses, in vertical blanking.
//
// ball_on is registered once, so it lines up with render.v's *_d flags (one
// clock behind pixel_x / pixel_y) and can be used directly as render's ball_on.
// The ball is the filled disc of radius BALL_RADIUS around (ball_sx, ball_sy)
// in screen pixels, so it is always round.
module ball_overlay (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,        // ball_physics phys_done
    input  wire signed [`POS_W-1:0]     ball_x,
    input  wire signed [`POS_W-1:0]     ball_y,
    input  wire signed [`TRIG_W-1:0]    sin_q,
    input  wire signed [`TRIG_W-1:0]    cos_q,
    input  wire [9:0]                   pixel_x,
    input  wire [9:0]                   pixel_y,
    input  wire                         active_video,
    output reg  signed [10:0]           ball_sx,      // screen position of the ball centre
    output reg  signed [10:0]           ball_sy,
    output reg                          ball_on
);

    localparam integer R  = `BALL_RADIUS;
    localparam integer R2 = `BALL_RADIUS * `BALL_RADIUS;

    // ---- position: 3 registered stages ----
    reg s1, s2;
    reg signed [`POS_W+`TRIG_W-1:0] p_xc, p_ys, p_xs, p_yc;       // Q10.22
    reg signed [`POS_W+`TRIG_W:0]   sx_q, sy_q;
    localparam integer FRAC = `POS_FRAC + `TRIG_FRAC;             // 22
    localparam signed [`POS_W+`TRIG_W:0] HALF = 1 <<< (FRAC - 1);

    always @(posedge clk) begin
        if (rst) begin
            s1 <= 1'b0; s2 <= 1'b0;
            ball_sx <= -11'sd100; ball_sy <= -11'sd100;     // off screen until the first position is computed
        end else begin
            s1 <= start;
            s2 <= s1;
            if (start) begin
                p_xc <= ball_x * cos_q;
                p_ys <= ball_y * sin_q;
                p_xs <= ball_x * sin_q;
                p_yc <= ball_y * cos_q;
            end
            if (s1) begin
                sx_q <= p_xc - p_ys;
                sy_q <= p_xs + p_yc;
            end
            if (s2) begin
                ball_sx <= `SCREEN_CX + ((sx_q + HALF) >>> FRAC);
                ball_sy <= `SCREEN_CY + ((sy_q + HALF) >>> FRAC);
            end
        end
    end

    // ---- per pixel: filled disc, squares from a tiny table (no multipliers) ----
    function [4:0] sq;
        input [3:0] n;
        begin
            case (n)
                4'd0: sq = 5'd0;
                4'd1: sq = 5'd1;
                4'd2: sq = 5'd4;
                4'd3: sq = 5'd9;
                4'd4: sq = 5'd16;
                default: sq = 5'd25;
            endcase
        end
    endfunction

    wire signed [11:0] dx = $signed({2'b00, pixel_x}) - ball_sx;
    wire signed [11:0] dy = $signed({2'b00, pixel_y}) - ball_sy;
    wire [11:0] adx = dx[11] ? -dx : dx;
    wire [11:0] ady = dy[11] ? -dy : dy;
    wire near = (adx <= R) && (ady <= R);
    wire [5:0] d2 = sq(adx[3:0]) + sq(ady[3:0]);

    always @(posedge clk) begin
        if (rst) ball_on <= 1'b0;
        else     ball_on <= active_video && near && (d2 <= R2);
    end

endmodule
