`timescale 1ns / 1ps

// oled_text_pixel: turns the 4x16 character buffer (AD-10) into the RGB565
// pixel stream that Oled_Display requests, as a function of pixel_index.
//   status_text: character k = row*16 + column is status_text[8*k +: 8], row 0 on top.
//   Layout on the 96x64 panel: a character cell is 6 px wide (5 glyph columns
//   + 1 blank), so 16 columns fill the 96 px; a text row is 16 px tall (each of
//   the 8 font lines is drawn twice), so 4 rows fill the 64 px.
//   Only ASCII 0x20..0x7E draw glyphs; anything else is blank.
// Timing: Oled_Display holds pixel_index stable for a whole 6.25 MHz cycle and
// loads pixel_data on the following falling edge; font_rom (registered, one
// clock of latency) captures on the rising edge in between. Run clk at 6.25 MHz.
module oled_text_pixel #(
    parameter [15:0] FG = 16'hFFFF,
    parameter [15:0] BG = 16'h0000
) (
    input  wire         clk,             // clk_6m25
    input  wire [12:0]  pixel_index,
    input  wire [511:0] status_text,
    output wire [15:0]  pixel_data
);

    wire [6:0] x;
    wire [5:0] y;
    oled_xy xy_i (.pixel_index(pixel_index), .x(x), .y(y));

    wire [3:0] cx   = x / 7'd6;                    // character column 0..15
    wire [2:0] gc   = x % 7'd6;                    // 0..4 glyph column, 5 blank
    wire [1:0] ty   = y[5:4];                      // text row 0..3
    wire [2:0] line = y[3:1];                      // font line 0..7 (bit 0 = top)
    wire [5:0] kidx = {ty, cx};
    wire [7:0] ch   = status_text[{kidx, 3'b000} +: 8];
    wire       in_glyph = (gc < 3'd5) && !ch[7];

    wire [7:0] font_data;
    font_rom font_i (.clk(clk), .ch(ch[6:0]), .col(in_glyph ? gc : 3'd0), .data(font_data));

    assign pixel_data = (in_glyph && font_data[line]) ? FG : BG;

endmodule
