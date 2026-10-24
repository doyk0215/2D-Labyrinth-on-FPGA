`timescale 1ns / 1ps

// Story 1.2 top: fixed maze rendered over the VGA timing generator.
module top (
    input  wire       clk,
    input  wire       btnC,
    input  wire       btnU,
    input  wire       btnL,
    input  wire       btnR,
    input  wire       btnD,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
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
    wire timing_hsync;
    wire timing_vsync;

    wire [8:0] maze_raddr_p;
    wire maze_rdata_p;
    wire [8:0] maze_raddr_r;
    wire maze_rdata_r;

    localparam [4:0] FIXED_START_COL = 5'd1;
    localparam [4:0] FIXED_START_ROW = 5'd1;
    localparam [4:0] FIXED_GOAL_COL  = 5'd1;
    localparam [4:0] FIXED_GOAL_ROW  = 5'd19;

    vga_timing timing_i (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync        (timing_hsync),
        .vsync        (timing_vsync)
    );

    // The map is preloaded for Story 1.2. Later maze_gen writes through
    // the same single write port; the physics port is idle in this story.
    assign maze_raddr_p = 9'd0;

    maze_ram maze_ram_i (
        .clk     (clk),
        .we      (1'b0),
        .waddr   (9'd0),
        .wdata   (1'b0),
        .raddr_p (maze_raddr_p),
        .rdata_p (maze_rdata_p),
        .raddr_r (maze_raddr_r),
        .rdata_r (maze_rdata_r)
    );

    render render_i (
        .clk          (clk),
        .rst          (rst),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync_in     (timing_hsync),
        .vsync_in     (timing_vsync),
        .maze_raddr   (maze_raddr_r),
        .maze_rdata   (maze_rdata_r),
        .start_col    (FIXED_START_COL),
        .start_row    (FIXED_START_ROW),
        .goal_col     (FIXED_GOAL_COL),
        .goal_row     (FIXED_GOAL_ROW),
        .vga_r        (vga_r),
        .vga_g        (vga_g),
        .vga_b        (vga_b),
        .vga_hs       (vga_hs),
        .vga_vs       (vga_vs)
    );

    // Not used until later stories. Keep LEDs low and the OLED idle. The
    // Pmod OLED VDDC/VBATC power controls are ACTIVE LOW (low = supply on),
    // so drive them high (off) until the OLED driver (Story 4.1) applies
    // the manual's power-up sequence. The PS/2 pins remain released for
    // the open-collector interface.
    assign led = 16'h0000;
    assign oled_cs = 1'b1;
    assign oled_mosi = 1'b0;
    assign oled_sclk = 1'b0;
    assign oled_dc = 1'b0;
    assign oled_res = 1'b0;
    assign oled_vbatc = 1'b1;
    assign oled_vddc = 1'b1;

endmodule
