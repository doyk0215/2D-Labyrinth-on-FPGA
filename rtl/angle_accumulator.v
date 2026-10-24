`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Frame-synchronous 12-bit maze angle accumulator.
// At a nominal 60 frames/s, 1024 angle counts/s is 90 degrees/s. Since
// 1024/60 is fractional, a remainder accumulator alternates 17- and
// 18-count steps while preserving the exact average. The actual VGA timing
// is about 59.52 frames/s, giving approximately 89.3 degrees/s.
module angle_accumulator (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    frame_tick,
    input  wire signed [1:0]       rot_cmd,
    output reg  [`ANGLE_W-1:0]     angle
);

    localparam [6:0] PHASE_MODULUS = 7'd60;
    localparam [6:0] PHASE_ADD     = 7'd4;  // 1024 = 17*60 + 4

    reg [5:0] phase_remainder;
    wire [6:0] phase_sum = {1'b0, phase_remainder} + PHASE_ADD;
    wire phase_carry = (phase_sum >= PHASE_MODULUS);
    wire [`ANGLE_W-1:0] angle_step = phase_carry ? 12'd18 : 12'd17;

    always @(posedge clk) begin
        if (rst) begin
            angle <= {`ANGLE_W{1'b0}};
            phase_remainder <= 6'd0;
        end else if (frame_tick) begin
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
                    // Both buttons, no buttons, or an invalid command means
                    // hold. Keep the fractional phase frozen while stopped.
                    angle <= angle;
                    phase_remainder <= phase_remainder;
                end
            endcase
        end
    end

endmodule
