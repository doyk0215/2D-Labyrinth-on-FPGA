`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Inverse-map the screen into the maze. Each scanline starts with two signed
// products; each following pixel needs only one add per coordinate. Coordinates
// are signed Q13.14 maze pixels. The screen centre shows the map centre plus
// the camera, which is (0, 0) on stages that fit the screen. The maze RAM and
// the output flags share one 100 MHz clock of latency. In WIN the goal tile blinks and the panel shows
// the timer; both are latched with the frame snapshot, so they never change
// in the middle of a picture. The fog of war flag (Story 9.4) is latched the
// same way; under fog only the ball and the pixels inside fog_clear are drawn.
module render #(
    parameter integer BLINK_FRAMES = 16,  // frames per blink phase, about 2 Hz at 60 Hz
    parameter integer BLAST_ENABLE = 0    // 1: tint the tiles of a wall breaker blast (needs the blast_* inputs)
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              ce_pix,
    input  wire              frame_tick,
    input  wire [`GAME_STATE_W-1:0] game_state,
    input  wire [7:0]        time_min_bcd,
    input  wire [7:0]        time_sec_bcd,
    input  wire [`N_CELLS_W-1:0] n_cells,
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
    output wire [`MAP_ADDR_W-1:0] maze_raddr,
    input  wire              maze_rdata,
    input  wire [`COORD_W-1:0] start_col,
    input  wire [`COORD_W-1:0] start_row,
    input  wire [`COORD_W-1:0] goal_col,
    input  wire [`COORD_W-1:0] goal_row,
    input  wire [8*`COORD_W-1:0] box_cols,  // item box k at bits [COORD_W*k +: COORD_W]
    input  wire [8*`COORD_W-1:0] box_rows,
    input  wire [7:0]        box_valid,     // from maze_gen
    input  wire [7:0]        box_visible,   // picked-up boxes are hidden
    input  wire              ball_on,       // from ball_overlay; lines up with the *_d flags below
    input  wire              fog_en,        // fog of war effect active (Story 9.4); latched per frame
    input  wire              fog_clear,     // from ball_overlay: pixel inside the fog circle, aligned with ball_on
    // Wall breaker explosion (blast_effect). Used only when BLAST_ENABLE is 1, so
    // benches that leave these unconnected are unaffected.
    input  wire              blast_on,
    input  wire              blast_fill,    // 1: every tile within blast_radius, 0: only the ring
    input  wire [1:0]        blast_radius,
    input  wire [`COORD_W-1:0] blast_col,
    input  wire [`COORD_W-1:0] blast_row,
    input  wire [11:0]       blast_rgb,
    output reg  [3:0]        vga_r,
    output reg  [3:0]        vga_g,
    output reg  [3:0]        vga_b,
    output reg               vga_hs,
    output reg               vga_vs,
    output wire              maze_pixel_visible,
    output reg  signed [15:0] sin_snap,     // this frame's sin/cos, for ball_overlay
    output reg  signed [15:0] cos_snap
);

    wire [`COORD_W-1:0] active_dim = {n_cells, 1'b0} + 1'b1;
    wire signed [26:0] n_ext = $signed({{(27-`N_CELLS_W){1'b0}}, n_cells});
    wire signed [26:0] active_centre_q = (n_ext <<< 18) + (27'sd8 <<< 14);
    wire signed [26:0] active_size_q = $signed({{(27-`COORD_W){1'b0}}, active_dim}) <<< 18;
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
    reg pause_frame;
    reg fog_frame;                          // fog of war for this picture (Story 9.4)
    reg gray_frame, menu_frame;
    reg [7:0] win_min_bcd, win_sec_bcd;
    reg [7:0] blink_count;
    reg blink_phase;
    wire win_panel, win_accent, win_text;
    wire lose_panel, lose_accent, lose_text;
    wire pause_panel, pause_accent, pause_text;
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
    pause_overlay pause_i (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .panel_on(pause_panel),
        .accent_on(pause_accent), .text_on(pause_text)
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
            pause_frame <= 1'b0;
            fog_frame <= 1'b0;
            gray_frame <= 1'b1;
            menu_frame <= 1'b1;
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
                pause_frame <= (game_state == `ST_PAUSED);
                // The effect can start or end at any clock; the picture
                // follows it from the next frame, never half way down.
                fog_frame <= fog_en;
                gray_frame <= (game_state != `ST_PLAY);
                menu_frame <= (game_state == `ST_MENU);
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
    wire [`COORD_W-1:0] tile_col_now = walk_x_q[18+`COORD_W-1:18];
    wire [`COORD_W-1:0] tile_row_now = walk_y_q[18+`COORD_W-1:18];
    // Every stage is stored with a fixed 64-tile row: addr = {row, col}.
    assign maze_raddr = in_map_now ? {tile_row_now, tile_col_now} : {`MAP_ADDR_W{1'b0}};

    wire [7:0] box_shown = box_valid & box_visible;
    wire [7:0] is_box_now;
    genvar bi;
    generate
        for (bi = 0; bi < 8; bi = bi + 1) begin : box_hit
            assign is_box_now[bi] = in_map_now && box_shown[bi] &&
                (tile_col_now == box_cols[`COORD_W*bi +: `COORD_W]) &&
                (tile_row_now == box_rows[`COORD_W*bi +: `COORD_W]);
        end
    endgenerate

    // Wall breaker explosion: Chebyshev tile distance from the blast centre.
    wire [`COORD_W-1:0] blast_dx = (tile_col_now > blast_col) ? tile_col_now - blast_col : blast_col - tile_col_now;
    wire [`COORD_W-1:0] blast_dy = (tile_row_now > blast_row) ? tile_row_now - blast_row : blast_row - tile_row_now;
    wire [`COORD_W-1:0] blast_dist = (blast_dx > blast_dy) ? blast_dx : blast_dy;
    wire [`COORD_W-1:0] blast_rad = {{(`COORD_W-2){1'b0}}, blast_radius};
    wire blast_hit_now = (BLAST_ENABLE != 0) && blast_on && in_map_now &&
                         (blast_fill ? (blast_dist <= blast_rad) : (blast_dist == blast_rad));
    reg blast_hit_d;
    function [11:0] mix12;      // per-channel average
        input [11:0] a, b;
        reg [4:0] sr, sg, sb;
        begin
            sr = {1'b0, a[11:8]} + {1'b0, b[11:8]};
            sg = {1'b0, a[7:4]}  + {1'b0, b[7:4]};
            sb = {1'b0, a[3:0]}  + {1'b0, b[3:0]};
            mix12 = {sr[4:1], sg[4:1], sb[4:1]};
        end
    endfunction
    reg in_map_d, is_start_d, is_goal_d, active_video_d;
    reg is_buff_d, is_debuff_d;
    reg [3:0] tile_px_d, tile_py_d;     // pixel inside the tile, maze space
    wire [11:0] wall_rgb_now;
    reg [11:0] wall_rgb_d;
    brick_wall_pixel wall_texture_i (
        .maze_x(walk_x_q[19:14]), .maze_y(walk_y_q[19:14]),
        .gray(gray_frame), .rgb(wall_rgb_now)
    );
    always @(posedge clk) begin
        if (rst) begin
            in_map_d <= 1'b0;
            blast_hit_d <= 1'b0;
            is_start_d <= 1'b0;
            is_goal_d <= 1'b0;
            is_buff_d <= 1'b0;
            is_debuff_d <= 1'b0;
            tile_px_d <= 4'd0;
            tile_py_d <= 4'd0;
            wall_rgb_d <= 12'h433;
            active_video_d <= 1'b0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            // maze_ram samples maze_raddr on this edge. These flags are
            // delayed by the same edge, so RAM data and RGB stay aligned.
            in_map_d <= in_map_now;
            blast_hit_d <= blast_hit_now;
            is_start_d <= in_map_now &&
                (tile_col_now == start_col) && (tile_row_now == start_row);
            is_goal_d <= in_map_now &&
                (tile_col_now == goal_col) && (tile_row_now == goal_row);
            // N=20 has four of each; N=15..19 has three; N=9..14 has two;
            // N=7..8 has one of each. N<=6 has no item boxes.
            if (n_cells == 20) begin
                is_buff_d <= |is_box_now[3:0];
                is_debuff_d <= |is_box_now[7:4];
            end else if (n_cells >= 15) begin
                is_buff_d <= |is_box_now[2:0];
                is_debuff_d <= |is_box_now[5:3];
            end else if (n_cells <= 8) begin
                is_buff_d <= is_box_now[0];
                is_debuff_d <= is_box_now[1];
            end else begin
                is_buff_d <= |is_box_now[1:0];
                is_debuff_d <= |is_box_now[3:2];
            end
            tile_px_d <= walk_x_q[17:14];
            tile_py_d <= walk_y_q[17:14];
            // Compute before the RAM-read edge; register alongside its address
            // flags so texturing adds no pixel latency or change to map data.
            wall_rgb_d <= wall_rgb_now;
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
            end else if (pause_frame && (pause_panel || pause_accent)) begin
                if (pause_text) begin
                    vga_r = 4'hf; vga_g = 4'hf; vga_b = 4'hf;
                end else if (pause_accent) begin
                    vga_r = 4'h0; vga_g = 4'hc; vga_b = 4'hf;
                end else begin
                    vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h3;
                end
            end else if (ball_on) begin
                vga_r = BALL_R; vga_g = BALL_G; vga_b = BALL_B;
            end else if (fog_frame && !fog_clear) begin
                // Fog of war: black outside the circle round the ball.
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
                    {vga_r, vga_g, vga_b} = blast_hit_d ? mix12(wall_rgb_d, blast_rgb) : wall_rgb_d;
                end else begin
                    {vga_r, vga_g, vga_b} = blast_hit_d ? mix12(menu_frame ? 12'h222 : {FLOOR_R, FLOOR_G, FLOOR_B}, blast_rgb) :
                                            menu_frame ? 12'h222 : {FLOOR_R, FLOOR_G, FLOOR_B};
                end
            end else begin
                {vga_r, vga_g, vga_b} = menu_frame ? 12'h111 : {BACK_R, BACK_G, BACK_B};
            end
        end
    end
endmodule
