`timescale 1ns / 1ps

// 640x480 VGA timing from the 100 MHz system clock. ce_pix is a clock
// enable; all state remains in the clk domain (no generated pixel clock).
module vga_timing (
    input  wire       clk,
    input  wire       rst,
    output wire       ce_pix,
    output wire       frame_tick,
    output reg  [9:0] pixel_x,
    output reg  [9:0] pixel_y,
    output wire       active_video,
    output wire       hsync,
    output wire       vsync
);

    localparam H_VISIBLE    = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC        = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = H_VISIBLE + H_FRONT_PORCH + H_SYNC + H_BACK_PORCH;

    localparam V_VISIBLE     = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC        = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_TOTAL       = V_VISIBLE + V_FRONT_PORCH + V_SYNC + V_BACK_PORCH;

    localparam H_SYNC_START = H_VISIBLE + H_FRONT_PORCH;
    localparam H_SYNC_END   = H_SYNC_START + H_SYNC;
    localparam V_SYNC_START = V_VISIBLE + V_FRONT_PORCH;
    localparam V_SYNC_END   = V_SYNC_START + V_SYNC;

    reg [1:0] pix_div;

    // Reset at 3 so the first enabled pixel after reset is (0, 0).
    always @(posedge clk) begin
        if (rst)
            pix_div <= 2'd3;
        else
            pix_div <= pix_div + 2'd1;
    end

    assign ce_pix = !rst && (pix_div == 2'd0);

    always @(posedge clk) begin
        if (rst) begin
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
        end else if (ce_pix) begin
            if (pixel_x == H_TOTAL - 1) begin
                pixel_x <= 10'd0;
                if (pixel_y == V_TOTAL - 1)
                    pixel_y <= 10'd0;
                else
                    pixel_y <= pixel_y + 10'd1;
            end else begin
                pixel_x <= pixel_x + 10'd1;
            end
        end
    end

    // Sync pulses are active low. frame_tick marks the first pixel of
    // vertical blanking, once per frame.
    assign hsync = !((pixel_x >= H_SYNC_START) && (pixel_x < H_SYNC_END));
    assign vsync = !((pixel_y >= V_SYNC_START) && (pixel_y < V_SYNC_END));
    assign active_video = (pixel_x < H_VISIBLE) && (pixel_y < V_VISIBLE);
    assign frame_tick = ce_pix && (pixel_x == 10'd0) && (pixel_y == V_VISIBLE);

endmodule
