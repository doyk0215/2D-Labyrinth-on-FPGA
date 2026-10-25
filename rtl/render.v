`timescale 1ns / 1ps

// Inverse-map the screen into the maze. Each scanline starts with two signed
// products; each following pixel needs only one add per coordinate. Coordinates
// are signed Q13.14 maze pixels. The maze RAM and the output flags share one
// 100 MHz clock of latency.
module render (
    input  wire              clk,
    input  wire              rst,
    input  wire              ce_pix,
    input  wire              frame_tick,
    input  wire [11:0]       angle,
    input  wire signed [15:0] sin_q,
    input  wire signed [15:0] cos_q,
    input  wire [9:0]        pixel_x,
    input  wire [9:0]        pixel_y,
    input  wire              active_video,
    input  wire              hsync_in,
    input  wire              vsync_in,
    output wire [8:0]       maze_raddr,
    input  wire              maze_rdata,
    input  wire [4:0]        start_col,
    input  wire [4:0]        start_row,
    input  wire [4:0]        goal_col,
    input  wire [4:0]        goal_row,
    output reg  [3:0]        vga_r,
    output reg  [3:0]        vga_g,
    output reg  [3:0]        vga_b,
    output reg               vga_hs,
    output reg               vga_vs
);

    localparam signed [26:0] MAP_CENTRE_Q = 27'sd168 <<< 14;
    localparam signed [26:0] MAP_SIZE_Q   = 27'sd336 <<< 14;
    localparam [3:0] WALL_R = 4'hf, WALL_G = 4'hf, WALL_B = 4'hf;
    localparam [3:0] FLOOR_R = 4'h3, FLOOR_G = 4'h4, FLOOR_B = 4'h6;
    localparam [3:0] START_R = 4'h0, START_G = 4'hf, START_B = 4'h0;
    localparam [3:0] GOAL_R = 4'hf, GOAL_G = 4'h0, GOAL_B = 4'h0;
    localparam [3:0] BACK_R = 4'h0, BACK_G = 4'h0, BACK_B = 4'h2;

    reg [1:0] frame_tick_d;
    reg [11:0] angle_snap;
    reg signed [15:0] sin_snap, cos_snap;
    reg signed [26:0] walk_x_q, walk_y_q;

    wire signed [26:0] sin_ext = {{11{sin_snap[15]}}, sin_snap};
    wire signed [26:0] cos_ext = {{11{cos_snap[15]}}, cos_snap};
    wire signed [10:0] next_dy = (pixel_y == 10'd524) ?
        -11'sd240 : $signed({1'b0, pixel_y}) - 11'sd239;
    wire signed [26:0] row_sin = next_dy * sin_snap;
    wire signed [26:0] row_cos = next_dy * cos_snap;

    // At x=0, dx=-320. Positive angle rotates clockwise on a screen whose
    // Y axis points down. Inverse-map screen (dx,dy) to maze pixels:
    // maze_x = 168 + dx*cos + dy*sin
    // maze_y = 168 - dx*sin + dy*cos
    wire signed [26:0] line_x_q = MAP_CENTRE_Q -
        (cos_ext <<< 8) - (cos_ext <<< 6) + row_sin;
    wire signed [26:0] line_y_q = MAP_CENTRE_Q +
        (sin_ext <<< 8) + (sin_ext <<< 6) + row_cos;

    always @(posedge clk) begin
        if (rst) begin
            frame_tick_d <= 2'b00;
            angle_snap <= 12'd0;
            sin_snap <= 16'sd0;
            cos_snap <= 16'sd16384;
            walk_x_q <= -(27'sd152 <<< 14);
            walk_y_q <= -(27'sd72 <<< 14);
        end else begin
            frame_tick_d <= {frame_tick_d[0], frame_tick};
            // The angle accumulator updates on frame_tick. The registered
            // sincos ROM sees that new angle one edge later. Capture both
            // together on the following edge, in vertical blanking.
            if (frame_tick_d[1]) begin
                angle_snap <= angle;
                sin_snap <= sin_q;
                cos_snap <= cos_q;
            end

            if (ce_pix) begin
                if (pixel_x == 10'd799) begin
                    // Timing advances to x=0 of the next scanline here.
                    walk_x_q <= line_x_q;
                    walk_y_q <= line_y_q;
                end else begin
                    walk_x_q <= walk_x_q + cos_ext;
                    walk_y_q <= walk_y_q - sin_ext;
                end
            end
        end
    end

    wire in_map_now = active_video &&
        (walk_x_q >= 0) && (walk_x_q < MAP_SIZE_Q) &&
        (walk_y_q >= 0) && (walk_y_q < MAP_SIZE_Q);
    wire [4:0] tile_col_now = walk_x_q[22:18];
    wire [4:0] tile_row_now = walk_y_q[22:18];
    wire [8:0] row_base_addr = {tile_row_now, 4'b0000} +
                               {2'b00, tile_row_now, 2'b00} +
                               {4'b0000, tile_row_now};
    assign maze_raddr = in_map_now ?
        row_base_addr + {4'b0000, tile_col_now} : 9'd0;

    reg in_map_d, is_start_d, is_goal_d, active_video_d;
    always @(posedge clk) begin
        if (rst) begin
            in_map_d <= 1'b0;
            is_start_d <= 1'b0;
            is_goal_d <= 1'b0;
            active_video_d <= 1'b0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            // maze_ram samples maze_raddr on this edge. These flags are
            // delayed by the same edge, so RAM data and RGB stay aligned.
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
