`timescale 1ns / 1ps

// oled_bringup_top: stand-alone hardware test for the Pmod OLED (Story 4.1).
// Not part of the game. To use it in Vivado, before synthesis run in the Tcl console:
//     set_property top oled_bringup_top [current_fileset]
// (switch back with: set_property top top [current_fileset]).
// The XDC also constrains ports this module does not have; Vivado only warns.
//
// Shows four fixed lines. Hold btnC to power the display down in order
// (display off, VBAT off, 100 ms, VDD off); release it to power up again.
// led[0] = display on, led[1] = shutdown requested.
module oled_bringup_top (
    input  wire        clk,
    input  wire        btnC,
    output wire [15:0] led,
    output wire        oled_cs,
    output wire        oled_mosi,
    output wire        oled_sclk,
    output wire        oled_dc,
    output wire        oled_res,
    output wire        oled_vbatc,
    output wire        oled_vddc
);

    // Four rows of 16 characters; character k is at bits [8*k +: 8], k = 0 top-left.
    function [511:0] pack_text;
        input [127:0] r0;   // first character in the most significant byte
        input [127:0] r1;
        input [127:0] r2;
        input [127:0] r3;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                pack_text[8 * i        +: 8] = r0[127 - 8 * i -: 8];
                pack_text[8 * (16 + i) +: 8] = r1[127 - 8 * i -: 8];
                pack_text[8 * (32 + i) +: 8] = r2[127 - 8 * i -: 8];
                pack_text[8 * (48 + i) +: 8] = r3[127 - 8 * i -: 8];
            end
        end
    endfunction

    wire [511:0] text = pack_text("2D LABYRINTH    ",
                                  "OLED TEST OK?   ",
                                  "ABC xyz 0123 !? ",
                                  "STAGE 1  00:00  ");

    // Synchronise the button (reset-less, only used as a level)
    reg [1:0] btn_sync = 2'b00;
    always @(posedge clk) btn_sync <= {btn_sync[0], btnC};
    wire shutdown = btn_sync[1];

    // Power-on reset for the driver (a few microseconds after configuration)
    reg [7:0] por = 8'd0;
    wire rst = (por != 8'hFF);
    always @(posedge clk) if (por != 8'hFF) por <= por + 8'd1;

    wire oled_on;
    oled_driver drv (
        .clk(clk), .rst(rst), .shutdown(shutdown), .status_text(text), .oled_on(oled_on),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    assign led = {14'd0, shutdown, oled_on};

endmodule
