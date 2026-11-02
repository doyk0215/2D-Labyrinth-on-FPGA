`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Inverse-map the screen into the maze. Each scanline starts with two signed
// products; each following pixel needs only one add per coordinate. Coordinates
// are signed Q13.14 maze pixels. The screen centre shows the map centre plus
// the camera, which is (0, 0) on stages that fit the screen. The maze RAM and
// the output flags share one 100 MHz clock of latency. In WIN the goal tile blinks and the panel shows
// the timer; both are latched with the frame snapshot, so they never change
// in the middle of a picture.
module render #(
    parameter integer BLINK_FRAMES = 16   // frames per blink phase, about 2 Hz at 60 Hz
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              ce_pix,
    input  wire              frame_tick,
    input  wire [`GAME_STATE_W-1:0] game_state,
    input  wire [7:0]        time_min_bcd,
    input  wire [7:0]        time_sec_bcd,
    input  wire [3:0]        n_cells,
    input  wire signed [`POS_W-1:0] cam_x,  // camera, Q9.8 from the map centre (Story 7.2)
    input  wire signed [`POS_W-1:0] cam_y,
    input  wire [11:0]       angle,
    input  wire signed [15:0] sin_q,
    input  wire signed [15:0] cos_q,
    input  wire [9:0]        pixel_x,
    input  wire [9:0]        pixel_y,
    input  wire              active_video,
    input  wire              hsync_in,
    input  wire              vsync_in,
    output wire [9:0]       maze_raddr,
    input  wire              maze_rdata,
    input  wire [4:0]        start_col,
    input  wire [4:0]        start_row,
    input  wire [4:0]        goal_col,
    input  wire [4:0]        goal_row,
    input  wire [19:0]       box_cols,      // item box k at bits 5k+4:5k (Story 9.1);
    input  wire [19:0]       box_rows,      // boxes 0 and 1 buff, 2 and 3 debuff
    input  wire [3:0]        box_valid,     // from maze_gen
    input  wire [3:0]        box_visible,   // picked-up boxes are hidden (Story 9.2)
    input  wire              ball_on,       // from ball_overlay; lines up with the *_d flags below
    output reg  [3:0]        vga_r,
    output reg  [3:0]        vga_g,
    output reg  [3:0]        vga_b,
    output reg               vga_hs,
    output reg               vga_vs,
    output wire              maze_pixel_visible,
    output reg  signed [15:0] sin_snap,     // this frame's sin/cos, for ball_overlay
    output reg  signed [15:0] cos_snap
);

    wire [4:0] active_dim = {n_cells, 1'b0} + 5'd1;
    wire signed [26:0] n_ext = $signed({23'd0, n_cells});
    wire signed [26:0] active_centre_q = (n_ext <<< 18) + (27'sd8 <<< 14);
    wire signed [26:0] active_size_q = $signed({22'd0, active_dim}) <<< 18;
    localparam [3:0] WALL_R = 4'hf, WALL_G = 4'hf, WALL_B = 4'hf;
    localparam [3:0] FLOOR_R = 4'h3, FLOOR_G = 4'h4, FLOOR_B = 4'h6;
    localparam [3:0] START_R = 4'hf, START_G = 4'h0, START_B = 4'h0;
    localparam [3:0] GOAL_R = 4'h0, GOAL_G = 4'hf, GOAL_B = 4'h0;
    localparam [3:0] BACK_R = 4'h0, BACK_G = 4'h0, BACK_B = 4'h2;
    localparam [3:0] BALL_R = 4'hf, BALL_G = 4'hc, BALL_B = 4'h0;
    localparam [11:0] BUFF_FILL = 12'h04f, BUFF_EDGE = 12'h0f0;
    localparam [11:0] DEBUFF_FILL = 12'hc00, DEBUFF_EDGE = 12'hf88;
    localparam [11:0] GLYPH_RGB = 12'hfff;

    // Item box on a 16 x 16 tile: floor margin at 0 and 15, outline at 1 and
    // 14, fill inside, and a white "?" in columns 5-10 of rows 3-11.
    function [15:0] glyph_row;
        input [3:0] y;
        begin
            case (y)
                4'd3:  glyph_row = 16'h03c0;   // .####.
                4'd4:  glyph_row = 16'h0660;   // ##..##
                4'd5:  glyph_row = 16'h0600;   // ....##
                4'd6:  glyph_row = 16'h0300;   // ...##.
                4'd7, 4'd8, 4'd10, 4'd11:
                       glyph_row = 16'h0180;   // ..##..
                default: glyph_row = 16'h0000;
            endcase
        end
    endfunction

    reg [1:0] frame_tick_d;
    reg [11:0] angle_snap;
    reg win_frame;
    reg lose_frame;
    reg [7:0] win_min_bcd, win_sec_bcd;
    reg [7:0] blink_count;
    reg blink_phase;
    wire win_panel, win_accent, win_text;
    wire lose_panel, lose_accent, lose_text;
    lose_overlay lose_i (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .panel_on(lose_panel),
        .accent_on(lose_accent), .text_on(lose_text)
    );
    win_overlay win_i (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video),
        .time_min_bcd(win_min_bcd), .time_sec_bcd(win_sec_bcd),
        .panel_on(win_panel),
        .accent_on(win_accent), .text_on(win_text)
    );
    reg signed [26:0] walk_x_q, walk_y_q;
    reg signed [10:0] next_dy;
    reg signed [26:0] row_sin, row_cos;

    wire signed [26:0] sin_ext = {{11{sin_snap[15]}}, sin_snap};
    wire signed [26:0] cos_ext = {{11{cos_snap[15]}}, cos_snap};
    wire signed [10:0] next_dy_now = (pixel_y == 10'd524) ?
        -11'sd240 : $signed({1'b0, pixel_y}) - 11'sd239;

    // pixel_y holds for a whole scanline and the snapshots change only in
    // vertical blanking, so the row products are registered in two stages
    // (dy, then the DSP product) long before the x=799 load uses them.
    always @(posedge clk) begin
        next_dy <= next_dy_now;
        row_sin <= next_dy * sin_snap;
        row_cos <= next_dy * cos_snap;
    end

    // At x=0, dx=-320. Positive angle rotates clockwise on a screen whose
    // Y axis points down. Inverse-map screen (dx,dy) to maze pixels about
    // the view centre (the map centre plus the camera, Story 7.3):
    // maze_x = view-centre + dx*cos + dy*sin
    // maze_y = view-centre - dx*sin + dy*cos
    // The per-frame part is registered. Its inputs (camera and trig snapshot)
    // change only in vertical blanking, so every visible line of a frame uses
    // one camera position, and the scanline load is a single add.
    wire signed [26:0] cam_x_q = $signed({{9{cam_x[`POS_W-1]}}, cam_x}) <<< 6;   // Q9.8 -> Q13.14
    wire signed [26:0] cam_y_q = $signed({{9{cam_y[`POS_W-1]}}, cam_y}) <<< 6;
    reg  signed [26:0] base_x_q, base_y_q;
    always @(posedge clk) begin
        base_x_q <= active_centre_q + cam_x_q - (cos_ext <<< 8) - (cos_ext <<< 6);
        base_y_q <= active_centre_q + cam_y_q + (sin_ext <<< 8) + (sin_ext <<< 6);
    end
    wire signed [26:0] line_x_q = base_x_q + row_sin;
    wire signed [26:0] line_y_q = base_y_q + row_cos;

    always @(posedge clk) begin
        if (rst) begin
            frame_tick_d <= 2'b00;
            angle_snap <= 12'd0;
            win_frame <= 1'b0;
            lose_frame <= 1'b0;
            win_min_bcd <= 8'h00;
            win_sec_bcd <= 8'h00;
            blink_count <= 8'd0;
            blink_phase <= 1'b0;
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
                // game_ctrl changes state on frame_tick. Capture its new
                // state with the angle/trig snapshot in vertical blanking.
                win_frame <= (game_state == `ST_WIN);
                lose_frame <= (game_state == `ST_LOSE);
                win_min_bcd <= time_min_bcd;
                win_sec_bcd <= time_sec_bcd;
                // The goal blink restarts bright on the first WIN frame and
                // flips every BLINK_FRAMES captured frames after that.
                if (game_state != `ST_WIN || !win_frame) begin
                    blink_count <= 8'd0;
                    blink_phase <= 1'b0;
                end else if (blink_count == BLINK_FRAMES - 1) begin
                    blink_count <= 8'd0;
                    blink_phase <= ~blink_phase;
                end else begin
                    blink_count <= blink_count + 8'd1;
                end
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
        (walk_x_q >= 0) && (walk_x_q < active_size_q) &&
        (walk_y_q >= 0) && (walk_y_q < active_size_q);
    wire [4:0] tile_col_now = walk_x_q[22:18];
    wire [4:0] tile_row_now = walk_y_q[22:18];
    // Every stage is stored with a fixed 32-tile row: addr = {row, col}.
    assign maze_raddr = in_map_now ? {tile_row_now, tile_col_now} : 10'd0;

    wire [3:0] box_shown = box_valid & box_visible;
    wire [3:0] is_box_now;
    genvar bi;
    generate
        for (bi = 0; bi < 4; bi = bi + 1) begin : box_hit
            assign is_box_now[bi] = in_map_now && box_shown[bi] &&
                (tile_col_now == box_cols[5*bi +: 5]) &&
                (tile_row_now == box_rows[5*bi +: 5]);
        end
    endgenerate

    reg in_map_d, is_start_d, is_goal_d, active_video_d;
    reg is_buff_d, is_debuff_d;
    reg [3:0] tile_px_d, tile_py_d;     // pixel inside the tile, maze space
    always @(posedge clk) begin
        if (rst) begin
            in_map_d <= 1'b0;
            is_start_d <= 1'b0;
            is_goal_d <= 1'b0;
            is_buff_d <= 1'b0;
            is_debuff_d <= 1'b0;
            tile_px_d <= 4'd0;
            tile_py_d <= 4'd0;
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
            is_buff_d <= |is_box_now[1:0];
            is_debuff_d <= |is_box_now[3:2];
            tile_px_d <= walk_x_q[17:14];
            tile_py_d <= walk_y_q[17:14];
            active_video_d <= active_video;
            vga_hs <= hsync_in;
            vga_vs <= vsync_in;
        end
    end

    // Align with the delayed map/background selection that drives VGA RGB.
    assign maze_pixel_visible = active_video_d && in_map_d;

    wire box_margin = (tile_px_d == 4'd0) || (tile_px_d == 4'd15) ||
                      (tile_py_d == 4'd0) || (tile_py_d == 4'd15);
    wire box_edge   = (tile_px_d == 4'd1) || (tile_px_d == 4'd14) ||
                      (tile_py_d == 4'd1) || (tile_py_d == 4'd14);
    wire [15:0] glyph_bits = glyph_row(tile_py_d);
    wire box_glyph  = glyph_bits[tile_px_d];
    wire [11:0] box_rgb = box_glyph ? GLYPH_RGB :
                          box_edge  ? (is_buff_d ? BUFF_EDGE : DEBUFF_EDGE) :
                                      (is_buff_d ? BUFF_FILL : DEBUFF_FILL);

    always @* begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;
        if (active_video_d) begin
            if (lose_frame && (lose_panel || lose_accent)) begin
                if (lose_text) begin
                    vga_r = 4'hf; vga_g = 4'hf; vga_b = 4'hf;
                end else if (lose_accent) begin
                    vga_r = 4'hf; vga_g = 4'h2; vga_b = 4'h2;
                end else begin
                    vga_r = 4'h3; vga_g = 4'h0; vga_b = 4'h0;
                end
            end else if (win_frame && (win_panel || win_accent)) begin
                if (win_text) begin
                    vga_r = 4'hf; vga_g = 4'hf; vga_b = 4'hf;
                end else if (win_accent) begin
                    vga_r = 4'h0; vga_g = 4'hf; vga_b = 4'h0;
                end else begin
                    vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h3;
                end
            end else if (ball_on) begin
                vga_r = BALL_R; vga_g = BALL_G; vga_b = BALL_B;
            end else if (in_map_d) begin
                if (is_start_d) begin
                    vga_r = START_R; vga_g = START_G; vga_b = START_B;
                end else if (is_goal_d) begin
                    if (win_frame && blink_phase) begin
                        vga_r = 4'h0; vga_g = 4'h3; vga_b = 4'h0;
                    end else begin
                        vga_r = GOAL_R; vga_g = GOAL_G; vga_b = GOAL_B;
                    end
                end else if ((is_buff_d || is_debuff_d) && !box_margin) begin
                    {vga_r, vga_g, vga_b} = box_rgb;
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
