`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Frame-synchronous 12-bit maze angle accumulator with a menu-selected rate.
// At a nominal 60 frames/s, 1024 angle counts/s is 90 degrees/s. Since
// 1024/60 is fractional, a remainder accumulator alternates 17- and
// 18-count steps while preserving the exact average. The actual VGA timing
// is about 59.52 frames/s, giving approximately 89.3 degrees/s.
module angle_accumulator (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    frame_tick,
    input  wire signed [1:0]       rot_cmd,
    input  wire [1:0]              rot_speed_sel,
    input  wire                    snap_mode,
    input  wire                    rot_held,
    output reg  [`ANGLE_W-1:0]     angle
);

    localparam [6:0] PHASE_MODULUS = 7'd60;
    reg [5:0] phase_remainder;
    reg [6:0] phase_add;
    reg [6:0] whole_step;
    always @* begin
        // Counts/second = whole_step * 60 + phase_add. Keep code 00 at
        // the historical 1024 counts/second (about 90 degrees/second).
        case (rot_speed_sel)
            2'b01: begin whole_step = 7'd8;  phase_add = 7'd32; end // 512 / s
            2'b10: begin whole_step = 7'd25; phase_add = 7'd36; end // 1536 / s
            2'b11: begin whole_step = 7'd34; phase_add = 7'd8;  end // 2048 / s
            default: begin whole_step = 7'd17; phase_add = 7'd4;  end // 1024 / s
        endcase
    end

    wire [6:0] phase_sum = {1'b0, phase_remainder} + phase_add;
    wire phase_carry = (phase_sum >= PHASE_MODULUS);
    wire [`ANGLE_W-1:0] angle_step = phase_carry ? whole_step + 1'b1 : whole_step;

    // Each complete press contributes one step. rot_held distinguishes "both pressed"
    // from "neither pressed", since input_mux reports zero for both cases.
    reg press_active;
    reg press_valid;
    reg signed [1:0] press_dir;
    reg pending_valid;
    reg [`ANGLE_W-1:0] pending_angle;
    wire valid_cmd = (rot_cmd == `ROT_CW) || (rot_cmd == `ROT_CCW);
    // Fold releases into the pending destination in order. This handles any
    // number of clicks per frame without a bounded queue; full turns wrap.
    // Using the destination also preserves directional rounding when the first
    // snap starts from a fractional angle inherited from smooth mode.
    wire [`ANGLE_W-1:0] snap_origin = pending_valid ? pending_angle : angle;
    wire [1:0] cw_quadrant = snap_origin[11:10] + 2'd1;
    wire [1:0] ccw_quadrant = snap_origin[11:10] -
                               ((snap_origin[9:0] == 10'd0) ? 2'd1 : 2'd0);

    always @(posedge clk) begin
        if (rst) begin
            angle <= {`ANGLE_W{1'b0}};
            phase_remainder <= 6'd0;
            press_active <= 1'b0;
            press_valid <= 1'b0;
            press_dir <= `ROT_NONE;
            pending_valid <= 1'b0;
            pending_angle <= {`ANGLE_W{1'b0}};
        end else if (snap_mode) begin
            // Consume accumulated releases only at frame start so the renderer
            // and later physics observe the same stable angle for a frame.
            if (frame_tick && pending_valid) begin
                angle <= pending_angle;
                pending_valid <= 1'b0;
            end

            if (!rot_held) begin
                if (press_active && press_valid) begin
                    if (press_dir == `ROT_CW)
                        pending_angle <= {cw_quadrant, 10'b0};
                    else
                        pending_angle <= {ccw_quadrant, 10'b0};
                    // A release on frame_tick extends the destination just
                    // consumed and remains pending for the following frame.
                    pending_valid <= 1'b1;
                end
                press_active <= 1'b0;
                press_valid <= 1'b0;
            end else if (!press_active) begin
                press_active <= 1'b1;
                press_valid <= valid_cmd;
                press_dir <= rot_cmd;
            end else if (rot_cmd != press_dir) begin
                // A simultaneous/opposite press cancels this gesture.
                press_valid <= 1'b0;
            end
        end else begin
            press_active <= 1'b0;
            press_valid <= 1'b0;
            pending_valid <= 1'b0;
            if (frame_tick) begin
                case (rot_cmd)
                    `ROT_CW: begin
                        angle <= angle + angle_step;
                        if (phase_carry)
                            phase_remainder <= phase_sum - PHASE_MODULUS;
                        else
                            phase_remainder <= phase_sum[5:0];
                    end
                    `ROT_CCW: begin
                        angle <= angle - angle_step;
                        if (phase_carry)
                            phase_remainder <= phase_sum - PHASE_MODULUS;
                        else
                            phase_remainder <= phase_sum[5:0];
                    end
                    default: begin
                        // Both buttons, no buttons, or an invalid command
                        // hold the angle and the fractional phase.
                        angle <= angle;
                        phase_remainder <= phase_remainder;
                    end
                endcase
            end
        end
    end

endmodule
