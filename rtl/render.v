`timescale 1ns / 1ps

// Axis-aligned 21x21 maze renderer for Story 1.2. A synchronous maze RAM
// read adds one clk of latency, so coordinates, active-video, and sync are
// pipelined together. Address generation uses shifts and adds, not a multiplier.
module render (
    input  wire       clk,
    input  wire       rst,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active_video,
    input  wire       hsync_in,
    input  wire       vsync_in,
    output wire [8:0] maze_raddr,
    input  wire       maze_rdata,
    input  wire [4:0] start_col,
    input  wire [4:0] start_row,
    input  wire [4:0] goal_col,
    input  wire [4:0] goal_row,
    output reg  [3:0] vga_r,
    output reg  [3:0] vga_g,
    output reg  [3:0] vga_b,
    output reg        vga_hs,
    output reg        vga_vs
);

    localparam MAP_X = 152;
    localparam MAP_Y = 72;
    localparam MAP_SIZE = 336;

    localparam [3:0] WALL_R = 4'hf, WALL_G = 4'hf, WALL_B = 4'hf;
    localparam [3:0] FLOOR_R = 4'h3, FLOOR_G = 4'h4, FLOOR_B = 4'h6;
    localparam [3:0] START_R = 4'h0, START_G = 4'hf, START_B = 4'h0;
    localparam [3:0] GOAL_R = 4'hf, GOAL_G = 4'h0, GOAL_B = 4'h0;
    localparam [3:0] BACK_R = 4'h0, BACK_G = 4'h0, BACK_B = 4'h2;

    wire in_map_now;
    wire [9:0] map_x_now;
    wire [9:0] map_y_now;
    wire [4:0] tile_col_now;
    wire [4:0] tile_row_now;
    wire [8:0] row_base_addr;

    reg in_map_d;
    reg is_start_d;
    reg is_goal_d;
    reg active_video_d;

    assign in_map_now = active_video &&
                        (pixel_x >= MAP_X) && (pixel_x < MAP_X + MAP_SIZE) &&
                        (pixel_y >= MAP_Y) && (pixel_y < MAP_Y + MAP_SIZE);
    assign map_x_now = pixel_x - MAP_X;
    assign map_y_now = pixel_y - MAP_Y;
    assign tile_col_now = map_x_now[8:4];
    assign tile_row_now = map_y_now[8:4];

    // row * 21 + col = row * (16 + 4 + 1) + col.
    assign row_base_addr = {tile_row_now, 4'b0000} +
                           {2'b00, tile_row_now, 2'b00} +
                           {4'b0000, tile_row_now};
    assign maze_raddr = in_map_now ? row_base_addr + {4'b0000, tile_col_now} : 9'd0;

    always @(posedge clk) begin
        if (rst) begin
            in_map_d <= 1'b0;
            is_start_d <= 1'b0;
            is_goal_d <= 1'b0;
            active_video_d <= 1'b0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            in_map_d <= in_map_now;
            is_start_d <= in_map_now &&
                          (tile_col_now == start_col) && (tile_row_now == start_row);
            is_goal_d <= in_map_now &&
                         (tile_col_now == goal_col) && (tile_row_now == goal_row);
            active_video_d <= active_video;
            vga_hs <= hsync_in;
            vga_vs <= vsync_in;
        end
    end

    always @* begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (active_video_d) begin
            if (in_map_d) begin
                if (is_start_d) begin
                    vga_r = START_R; vga_g = START_G; vga_b = START_B;
                end else if (is_goal_d) begin
                    vga_r = GOAL_R; vga_g = GOAL_G; vga_b = GOAL_B;
                end else if (maze_rdata) begin
                    vga_r = WALL_R; vga_g = WALL_G; vga_b = WALL_B;
                end else begin
                    vga_r = FLOOR_R; vga_g = FLOOR_G; vga_b = FLOOR_B;
                end
            end else begin
                vga_r = BACK_R; vga_g = BACK_G; vga_b = BACK_B;
            end
        end
    end

endmodule
