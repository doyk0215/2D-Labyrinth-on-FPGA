`timescale 1ns / 1ps

// Story 1.1 bring-up top: stable VGA colour bars and safe inactive levels
// on the unused peripherals. Later stories replace the test pattern.
module top (
    input  wire       clk,
    input  wire       btnC,
    input  wire       btnU,
    input  wire       btnL,
    input  wire       btnR,
    input  wire       btnD,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output reg  [3:0] vga_r,
    output reg  [3:0] vga_g,
    output reg  [3:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs,
    inout  wire       ps2_clk,
    inout  wire       ps2_data,
    output wire       oled_cs,
    output wire       oled_mosi,
    output wire       oled_sclk,
    output wire       oled_dc,
    output wire       oled_res,
    output wire       oled_vbatc,
    output wire       oled_vddc
);

    wire rst = btnC;
    wire ce_pix;
    wire frame_tick;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;

    vga_timing timing_i (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync        (vga_hs),
        .vsync        (vga_vs)
    );

    // Eight 80-pixel colour bars; output black during blanking and reset.
    always @* begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;
        if (active_video && !rst) begin
            if (pixel_x < 10'd80) begin       // white
                vga_r = 4'hf; vga_g = 4'hf; vga_b = 4'hf;
            end else if (pixel_x < 10'd160) begin // yellow
                vga_r = 4'hf; vga_g = 4'hf; vga_b = 4'h0;
            end else if (pixel_x < 10'd240) begin // cyan
                vga_r = 4'h0; vga_g = 4'hf; vga_b = 4'hf;
            end else if (pixel_x < 10'd320) begin // green
                vga_r = 4'h0; vga_g = 4'hf; vga_b = 4'h0;
            end else if (pixel_x < 10'd400) begin // magenta
                vga_r = 4'hf; vga_g = 4'h0; vga_b = 4'hf;
            end else if (pixel_x < 10'd480) begin // red
                vga_r = 4'hf; vga_g = 4'h0; vga_b = 4'h0;
            end else if (pixel_x < 10'd560) begin // blue
                vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'hf;
            end
        end
    end

    // Not used until later stories. Keep LEDs and OLED power/control low;
    // the PS/2 pins remain released for the open-collector interface.
    assign led = 16'h0000;
    assign oled_cs = 1'b1;
    assign oled_mosi = 1'b0;
    assign oled_sclk = 1'b0;
    assign oled_dc = 1'b0;
    assign oled_res = 1'b0;
    assign oled_vbatc = 1'b0;
    assign oled_vddc = 1'b0;

endmodule
