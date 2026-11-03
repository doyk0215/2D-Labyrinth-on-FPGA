`timescale 1ns / 1ps

// Four-digit active-low Basys 3 display for the game's MM.SS countdown.
// The BCD inputs come directly from game_timer, so time bonuses are reflected
// without a second counter or a separate synchronization path.
module seven_seg_timer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer DIGIT_REFRESH_HZ = 1_000,
    parameter integer COLON_BLINK_HZ = 1
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [7:0] minutes_bcd,
    input  wire [7:0] seconds_bcd,
    output reg  [6:0] seg,
    output reg        dp,
    output reg  [3:0] an
);
    localparam integer RAW_DIV = CLK_HZ / (4 * DIGIT_REFRESH_HZ);
    localparam integer SCAN_DIV = (RAW_DIV > 0) ? RAW_DIV : 1;
    localparam integer COUNT_W = (SCAN_DIV > 1) ? $clog2(SCAN_DIV) : 1;
    localparam integer RAW_BLINK_HALF = CLK_HZ / (2 * COLON_BLINK_HZ);
    localparam integer BLINK_HALF_DIV = (RAW_BLINK_HALF > 0) ? RAW_BLINK_HALF : 1;
    localparam integer BLINK_COUNT_W = (BLINK_HALF_DIV > 1) ? $clog2(BLINK_HALF_DIV) : 1;

    reg [COUNT_W-1:0] scan_count = 0;
    reg [1:0] scan_digit = 0;
    reg [BLINK_COUNT_W-1:0] blink_count = 0;
    reg separator_on = 1'b1;
    reg [3:0] digit_value;

    always @(posedge clk) begin
        if (rst) begin
            scan_count <= 0;
            scan_digit <= 0;
            blink_count <= 0;
            separator_on <= 1'b1;
        end else begin
            if (scan_count == SCAN_DIV - 1) begin
                scan_count <= 0;
                scan_digit <= scan_digit + 1'b1;
            end else begin
                scan_count <= scan_count + 1'b1;
            end

            if (blink_count == BLINK_HALF_DIV - 1) begin
                blink_count <= 0;
                separator_on <= ~separator_on;
            end else begin
                blink_count <= blink_count + 1'b1;
            end
        end
    end

    always @* begin
        digit_value = 4'hf;
        an = 4'b1111;
        seg = 7'b1111111;
        dp = 1'b1;
        if (enable) begin
            an = ~(4'b0001 << scan_digit);
            case (scan_digit)
                2'd0: digit_value = seconds_bcd[3:0];
                2'd1: digit_value = seconds_bcd[7:4];
                2'd2: digit_value = minutes_bcd[3:0];
                2'd3: digit_value = minutes_bcd[7:4];
            endcase

            // Basys 3 has no two-dot colon, so blink the MM/SS separator point.
            if ((scan_digit == 2'd2) && separator_on) dp = 1'b0;
            case (digit_value)
                4'd0: seg = 7'b1000000;
                4'd1: seg = 7'b1111001;
                4'd2: seg = 7'b0100100;
                4'd3: seg = 7'b0110000;
                4'd4: seg = 7'b0011001;
                4'd5: seg = 7'b0010010;
                4'd6: seg = 7'b0000010;
                4'd7: seg = 7'b1111000;
                4'd8: seg = 7'b0000000;
                4'd9: seg = 7'b0010000;
                default: seg = 7'b1111111;
            endcase
        end
    end
endmodule
