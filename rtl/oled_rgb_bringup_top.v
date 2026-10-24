`timescale 1ns / 1ps

// oled_rgb_bringup_top: stand-alone board test for the Pmod OLEDrgb (96x64,
// SSD1331) using the course-supplied Oled_Display. Not part of the game.
// In Vivado: set_property top oled_rgb_bringup_top [get_filesets sources_1]
//
// Pmod OLEDrgb pin 9 is VCCEN and pin 10 is PMODEN (both active high). The
// shared XDC still calls those pins oled_vbatc / oled_vddc, so:
//   oled_vbatc = VCCEN, oled_vddc = PMODEN.
// Hold btnC to reset the display; release to power it up again.
// led[0] = VCCEN, led[1] = PMODEN, led[2] = sending pixels.
module oled_rgb_bringup_top (
    input  wire        clk,
    input  wire        btnC,
    output wire [15:0] led,
    output wire        oled_cs,
    output wire        oled_mosi,
    output wire        oled_sclk,
    output wire        oled_dc,
    output wire        oled_res,
    output wire        oled_vbatc,   // VCCEN
    output wire        oled_vddc     // PMODEN
);

    // Power-on reset in the 100 MHz domain, plus the button
    reg [7:0] por = 8'd0;
    always @(posedge clk) if (por != 8'hFF) por <= por + 8'd1;
    wire rst_100 = (por != 8'hFF) | btnC;

    wire clk_6m25;
    oled_clk_div div_i (.clk(clk), .clk_6m25(clk_6m25));

    // Bring the reset into the 6.25 MHz domain (same source clock, so synchronous)
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_6m25) rst_sync <= {rst_sync[0], rst_100};

    wire [12:0] pixel_index;
    wire [15:0] pixel_data;
    wire        frame_begin, sending_pixels, sample_pixel;

    oled_test_pattern pattern_i (.pixel_index(pixel_index), .pixel_data(pixel_data));

    Oled_Display oled_i (
        .clk            (clk_6m25),
        .reset          (rst_sync[1]),
        .frame_begin    (frame_begin),
        .sending_pixels (sending_pixels),
        .sample_pixel   (sample_pixel),
        .pixel_index    (pixel_index),
        .pixel_data     (pixel_data),
        .cs             (oled_cs),
        .sdin           (oled_mosi),
        .sclk           (oled_sclk),
        .d_cn           (oled_dc),
        .resn           (oled_res),
        .vccen          (oled_vbatc),
        .pmoden         (oled_vddc)
    );

    assign led = {13'd0, sending_pixels, oled_vddc, oled_vbatc};

endmodule
