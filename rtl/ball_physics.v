`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// ball_physics: ball state and gravity (Story 3.1, AD-3 / AD-4 / AD-6).
//
// Position and velocity live in MAZE coordinates (x right, y down as the maze
// is drawn at angle 0). Position is signed Q9.8 maze pixels measured from the
// centre of the 21x21 map; velocity is signed Q4.8 pixels per frame.
//
// Screen-down seen from the maze frame. render.v maps a screen offset
// (dx, dy) from the screen centre to maze pixels as
//     maze_x = 168 + dx*cos + dy*sin,   maze_y = 168 - dx*sin + dy*cos,
// so the screen-down direction (0, +1) is (sin, cos) in the maze frame:
//     gravity = g * (sin(theta), cos(theta)),   g = 0.25 px/frame^2.
// (The earlier AD-3 text said (-sin, cos); that does not match render.v.)
//
// One update per frame, in vertical blanking, after the angle accumulator and
// the registered sincos_rom have settled (the same moment render snapshots):
//     velocity += gravity, clamped to +/-VEL_CAP per axis
//     position += velocity (the new velocity)
// This story has no walls yet. To keep the position finite the ball stops at
// the edge of the map (velocity of that axis set to 0). Story 3.2 replaces
// that with tile collisions.
module ball_physics (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         frame_tick,
    input  wire                         phys_init,    // pulse: place the ball at the start tile, velocity 0
    input  wire                         phys_en,      // 1 = PLAY: apply gravity
    input  wire [`COORD_W-1:0]          start_col,
    input  wire [`COORD_W-1:0]          start_row,
    input  wire signed [`TRIG_W-1:0]    sin_q,
    input  wire signed [`TRIG_W-1:0]    cos_q,
    output reg  signed [`POS_W-1:0]     ball_x,
    output reg  signed [`POS_W-1:0]     ball_y,
    output reg  signed [`VEL_W-1:0]     vel_x,
    output reg  signed [`VEL_W-1:0]     vel_y,
    output reg                          phys_done     // pulse once the new position is valid
);

    // Ball centre stays at least one radius inside the map edge (168 px half-size).
    localparam signed [`POS_W-1:0] LIMIT = (168 - `BALL_RADIUS) * 256;
    localparam signed [`VEL_W-1:0] CAP   = `VEL_CAP;
    localparam integer ROUND = 1 << (`GRAV_SHIFT - 1);

    // frame_tick -> angle updates -> registered ROM: sin/cos are valid when ft_d[1] is high
    reg [1:0] ft_d;
    reg       go2, go3;

    // gravity step, in Q4.8 units per frame (|g| <= 64)
    reg signed [`VEL_W-1:0] gx, gy;

    // tile (col,row) has its centre at 16*(col-10) px from the map centre -> (col-10) << 12 in Q9.8
    wire signed [`POS_W-1:0] start_x = ($signed({1'b0, start_col}) - 6'sd10) <<< 12;
    wire signed [`POS_W-1:0] start_y = ($signed({1'b0, start_row}) - 6'sd10) <<< 12;

    wire signed [`VEL_W:0]   vx_sum = vel_x + gx;
    wire signed [`VEL_W:0]   vy_sum = vel_y + gy;
    wire signed [`POS_W:0]   px_sum = ball_x + vel_x;
    wire signed [`POS_W:0]   py_sum = ball_y + vel_y;

    always @(posedge clk) begin
        phys_done <= 1'b0;
        if (rst) begin
            ft_d <= 2'b00; go2 <= 1'b0; go3 <= 1'b0;
            gx <= 0; gy <= 0;
            ball_x <= 0; ball_y <= 0; vel_x <= 0; vel_y <= 0;
        end else begin
            ft_d <= {ft_d[0], frame_tick};
            go2  <= ft_d[1] & phys_en;
            go3  <= go2;

            // stage 1: gravity from the settled sin/cos (rounded arithmetic shift)
            if (ft_d[1]) begin
                gx <= (sin_q + ROUND) >>> `GRAV_SHIFT;
                gy <= (cos_q + ROUND) >>> `GRAV_SHIFT;
            end

            // stage 2: velocity, capped per axis
            if (go2) begin
                vel_x <= (vx_sum >  CAP) ?  CAP : (vx_sum < -CAP) ? -CAP : vx_sum[`VEL_W-1:0];
                vel_y <= (vy_sum >  CAP) ?  CAP : (vy_sum < -CAP) ? -CAP : vy_sum[`VEL_W-1:0];
            end

            // stage 3: position, stopped at the map edge
            if (go3) begin
                if (px_sum > LIMIT)       begin ball_x <=  LIMIT; vel_x <= 0; end
                else if (px_sum < -LIMIT) begin ball_x <= -LIMIT; vel_x <= 0; end
                else                            ball_x <= px_sum[`POS_W-1:0];
                if (py_sum > LIMIT)       begin ball_y <=  LIMIT; vel_y <= 0; end
                else if (py_sum < -LIMIT) begin ball_y <= -LIMIT; vel_y <= 0; end
                else                            ball_y <= py_sum[`POS_W-1:0];
                phys_done <= 1'b1;
            end

            // a new maze puts the ball back on the start tile, at rest
            if (phys_init) begin
                ball_x <= start_x; ball_y <= start_y;
                vel_x  <= 0;       vel_y  <= 0;
                go2 <= 1'b0; go3 <= 1'b0;
            end
        end
    end

endmodule
