`timescale 1ns / 1ps

// oled_test_pattern: RGB565 test image for the 96x64 Pmod OLEDrgb, a pure
// function of pixel_index (index = y * 96 + x), as Oled_Display requires.
//   - 1 px white border (checks that the whole 96x64 area is shown)
//   - rows 1..47: eight 12 px bars: white, yellow, cyan, green, magenta, red, blue, black
//   - rows 48..62: grey ramp, black on the left to white on the right
// A flipped or mirrored panel shows up as a reversed bar order or ramp.
module oled_test_pattern (
    input  wire [12:0] pixel_index,
    output reg  [15:0] pixel_data
);

    wire [7:0]  y_hi = pixel_index[12:5];           // index / 32
    wire [5:0]  y    = y_hi / 8'd3;                 // index / 96
    wire [12:0] row_base = {1'b0, y, 6'b0} + {2'b0, y, 5'b0}; // 96 * y
    wire [6:0]  x    = pixel_index - row_base;      // index % 96
    wire [2:0]  bar  = x / 7'd12;
    wire [4:0]  grey = x / 7'd3;                    // 0..31

    always @* begin
        if (x == 7'd0 || x == 7'd95 || y == 6'd0 || y == 6'd63)
            pixel_data = 16'hFFFF;
        else if (y >= 6'd48)
            pixel_data = {grey, grey, grey[4], grey};
        else
            case (bar)
                3'd0:    pixel_data = 16'hFFFF; // white
                3'd1:    pixel_data = 16'hFFE0; // yellow
                3'd2:    pixel_data = 16'h07FF; // cyan
                3'd3:    pixel_data = 16'h07E0; // green
                3'd4:    pixel_data = 16'hF81F; // magenta
                3'd5:    pixel_data = 16'hF800; // red
                3'd6:    pixel_data = 16'h001F; // blue
                default: pixel_data = 16'h0000; // black
            endcase
    end

endmodule
