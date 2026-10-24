`timescale 1ns / 1ps

// oled_xy: split the Oled_Display pixel index (index = y * 96 + x) into x, y.
// Shifts and adds only, no multiplier; the divide by 3 is on an 8-bit value.
module oled_xy (
    input  wire [12:0] pixel_index,
    output wire [6:0]  x,            // 0..95
    output wire [5:0]  y             // 0..63
);

    wire [7:0]  y_hi     = pixel_index[12:5];            // index / 32
    assign y = y_hi / 8'd3;                              // index / 96
    wire [12:0] row_base = {1'b0, y, 6'b0} + {2'b0, y, 5'b0};   // 96 * y
    assign x = pixel_index - row_base;

endmodule
