`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// camera: where the view of a large maze is centred (Story 7.2).
//
// cam_x / cam_y are signed Q9.8 maze pixels from the map centre, the ball's
// format. They update once per frame, two clocks after ball_physics'
// phys_done, so they use this frame's ball position:
//   1. Dead zone. The target holds while the ball is within +/-DEAD_ZONE_PX
//      of it on an axis; otherwise it moves just far enough to put the ball
//      back on the box edge. Bounces (up to about 47 px) stay inside the box,
//      so the view does not shake.
//   2. Smoothing. cam += (target - cam) >>> CAM_SHIFT, shift and add only.
//      The step is never larger than the gap, so the camera cannot overshoot.
// One clock after phys_init (new maze, replay, reset), when the ball is on
// its spawn tile, the target and the camera jump straight to the ball.
//
// Stages with n_cells < FOLLOW_MIN_N fit on screen at every angle and keep
// the fixed view: the camera is the map centre (0, 0). The choice is taken on
// phys_init, so a change of n_cells moves the camera only with the next snap.
// cam_done pulses for one clock with every new camera value, and the camera
// changes on no other clock except reset.
module camera #(
    parameter integer DEAD_ZONE_PX = 48,
    parameter integer CAM_SHIFT    = 3,
    parameter integer FOLLOW_MIN_N = 11
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         phys_init,    // game_ctrl: ball placed at spawn
    input  wire                         phys_done,    // ball_physics: new position valid
    input  wire [`N_CELLS_W-1:0]        n_cells,
    input  wire signed [`POS_W-1:0]     ball_x,
    input  wire signed [`POS_W-1:0]     ball_y,
    output wire signed [`POS_W-1:0]     cam_x,
    output wire signed [`POS_W-1:0]     cam_y,
    output reg                          cam_done
);

    // One extra bit: a target is up to DEAD_ZONE_PX beyond the ball, and
    // target - cam spans twice that range.
    localparam integer W = `POS_W + 1;
    localparam signed [W-1:0] DZ = DEAD_ZONE_PX <<< `POS_FRAC;

    reg follow;                                  // this game's stage needs the camera
    reg signed [W-1:0] tgt_x, tgt_y, cam_xr, cam_yr;
    reg init_d, step;

    wire signed [W-1:0] bx = ball_x;
    wire signed [W-1:0] by = ball_y;

    // the target that keeps the ball inside the box around it
    wire signed [W-1:0] tgt_x_next = (bx > tgt_x + DZ) ? bx - DZ :
                                     (bx < tgt_x - DZ) ? bx + DZ : tgt_x;
    wire signed [W-1:0] tgt_y_next = (by > tgt_y + DZ) ? by - DZ :
                                     (by < tgt_y - DZ) ? by + DZ : tgt_y;

    wire signed [W-1:0] gap_x = tgt_x - cam_xr;
    wire signed [W-1:0] gap_y = tgt_y - cam_yr;

    always @(posedge clk) begin
        if (rst) begin
            tgt_x <= 0; tgt_y <= 0; cam_xr <= 0; cam_yr <= 0;
            init_d <= 1'b0; step <= 1'b0; cam_done <= 1'b0; follow <= 1'b0;
        end else begin
            init_d   <= phys_init;
            if (phys_init) follow <= (n_cells >= FOLLOW_MIN_N);
            step     <= 1'b0;
            cam_done <= 1'b0;
            if (!follow) begin
                tgt_x <= 0; tgt_y <= 0; cam_xr <= 0; cam_yr <= 0;
                cam_done <= init_d || step;
                step <= phys_done && !phys_init;
            end else if (init_d) begin
                tgt_x <= bx; tgt_y <= by; cam_xr <= bx; cam_yr <= by;
                cam_done <= 1'b1;
            end else if (step) begin
                cam_xr <= cam_xr + (gap_x >>> CAM_SHIFT);
                cam_yr <= cam_yr + (gap_y >>> CAM_SHIFT);
                cam_done <= 1'b1;
            end else if (phys_done && !phys_init) begin
                tgt_x <= tgt_x_next;
                tgt_y <= tgt_y_next;
                step  <= 1'b1;
            end
        end
    end

    // Within the map |cam| stays under 512 px, so it fits the ball's width.
    assign cam_x = cam_xr[`POS_W-1:0];
    assign cam_y = cam_yr[`POS_W-1:0];

endmodule
