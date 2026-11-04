`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 9.4 fog of war. Two renderers share every input except fog_en: the
// reference never has fog. Under fog a pixel must equal the reference when an
// independent integer model puts it within the radius of the ball's screen
// centre, and be black otherwise. Every pixel of whole frames is checked,
// at 0 and 45 degrees and with the circle clipped by the screen edge.
module tb_fog_render;
    localparam integer R = 48;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg ce_pix = 1'b0;
    reg frame_tick = 1'b0;
    reg [11:0] angle = 12'd0;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] pixel_y = 10'd0;
    reg active_video = 1'b0;
    reg fog_en = 1'b0;
    reg start = 1'b0;
    reg signed [17:0] ball_x = 0, ball_y = 0;
    wire signed [15:0] sin_q, cos_q;
    wire signed [15:0] sin_snap, cos_snap;
    wire [`MAP_ADDR_W-1:0] addr_f, addr_n;
    wire data_f, data_n;
    wire [3:0] r_f, g_f, b_f, r_n, g_n, b_n;
    wire signed [10:0] ball_sx, ball_sy;
    wire ball_on, fog_clear;

    always #5 clk = ~clk;

    sincos_rom trig_i (.clk(clk), .angle(angle), .sin_q(sin_q), .cos_q(cos_q));
    maze_ram ram_f (
        .clk(clk), .we(1'b0), .waddr(10'd0), .wdata(1'b0),
        .raddr_p({`MAP_ADDR_W{1'b0}}), .rdata_p(), .ren_r(1'b1), .raddr_r(addr_f), .rdata_r(data_f)
    );
    maze_ram ram_n (
        .clk(clk), .we(1'b0), .waddr(10'd0), .wdata(1'b0),
        .raddr_p({`MAP_ADDR_W{1'b0}}), .rdata_p(), .ren_r(1'b1), .raddr_r(addr_n), .rdata_r(data_n)
    );
    ball_overlay #(.FOG_RADIUS(R)) ball_i (
        .clk(clk), .rst(rst), .start(start), .ball_x(ball_x), .ball_y(ball_y),
        .cam_x(18'sd0), .cam_y(18'sd0), .sin_q(sin_snap), .cos_q(cos_snap),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .ball_sx(ball_sx), .ball_sy(ball_sy), .ball_on(ball_on), .fog_clear(fog_clear)
    );
    // Same boxes as tb_rotated_render, so fog must hide boxes too.
    render fog_i (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(`ST_PLAY), .n_cells(5'd10), .cam_x(18'sd0), .cam_y(18'sd0),
        .time_min_bcd(8'h00), .time_sec_bcd(8'h00),
        .angle(angle), .sin_q(sin_q), .cos_q(cos_q),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .hsync_in(1'b1), .vsync_in(1'b1), .maze_raddr(addr_f), .maze_rdata(data_f),
        .start_col(6'd1), .start_row(6'd1), .goal_col(6'd1), .goal_row(6'd19),
        .box_cols({6'd13, 6'd15, 6'd9, 6'd5}), .box_rows({6'd15, 6'd9, 6'd13, 6'd5}),
        .box_valid(4'b1111), .box_visible(4'b1111),
        .ball_on(ball_on), .fog_en(fog_en), .fog_clear(fog_clear),
        .vga_r(r_f), .vga_g(g_f), .vga_b(b_f), .vga_hs(), .vga_vs(),
        .maze_pixel_visible(), .sin_snap(sin_snap), .cos_snap(cos_snap)
    );
    render ref_i (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(`ST_PLAY), .n_cells(5'd10), .cam_x(18'sd0), .cam_y(18'sd0),
        .time_min_bcd(8'h00), .time_sec_bcd(8'h00),
        .angle(angle), .sin_q(sin_q), .cos_q(cos_q),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .hsync_in(1'b1), .vsync_in(1'b1), .maze_raddr(addr_n), .maze_rdata(data_n),
        .start_col(6'd1), .start_row(6'd1), .goal_col(6'd1), .goal_row(6'd19),
        .box_cols({6'd13, 6'd15, 6'd9, 6'd5}), .box_rows({6'd15, 6'd9, 6'd13, 6'd5}),
        .box_valid(4'b1111), .box_visible(4'b1111),
        .ball_on(ball_on), .fog_en(1'b0), .fog_clear(fog_clear),
        .vga_r(r_n), .vga_g(g_n), .vga_b(b_n), .vga_hs(), .vga_vs(),
        .maze_pixel_visible(), .sin_snap(), .cos_snap()
    );

    integer checked, clear_seen, dark_seen, edge_in, edge_out, ball_seen, black_ref;

    task fail;
        input [511:0] reason;
        input integer x, y;
        begin
            $display("FAIL fog render: %0s at pixel=(%0d,%0d) fog=%h ref=%h ball=(%0d,%0d)",
                     reason, x, y, {r_f, g_f, b_f}, {r_n, g_n, b_n}, ball_sx, ball_sy);
            $finish;
        end
    endtask

    // Frame boundary: angle and fog flag are latched by render, then the
    // ball's screen position is computed from that frame's trig snapshot.
    task new_frame;
        input [11:0] new_angle;
        input signed [17:0] bx, by;
        begin
            @(negedge clk);
            ce_pix = 1'b0; active_video = 1'b0;
            angle = new_angle; ball_x = bx; ball_y = by;
            repeat (3) @(posedge clk);
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            repeat (6) @(posedge clk);
        end
    endtask

    // One scanline. mode 1: fogged picture against the model; mode 0: the
    // fogged renderer must match the reference everywhere (no fog shown).
    task check_line;
        input integer y;
        input integer mode;
        integer x, dx, dy, d2;
        reg inside;
        begin
            @(negedge clk);
            pixel_x = 10'd798;
            pixel_y = (y == 0) ? 10'd524 : y - 1;
            active_video = 1'b0; ce_pix = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            pixel_x = 10'd799; ce_pix = 1'b1;
            @(posedge clk); #1;
            for (x = 0; x < 640; x = x + 1) begin
                @(negedge clk);
                pixel_x = x; pixel_y = y; active_video = 1'b1;
                dx = x - ball_sx; dy = y - ball_sy;
                d2 = dx * dx + dy * dy;
                inside = (d2 <= R * R);
                @(posedge clk); #1;
                checked = checked + 1;
                if (ball_on) ball_seen = ball_seen + 1;
                if (mode == 0 || inside) begin
                    if ({r_f, g_f, b_f} !== {r_n, g_n, b_n})
                        fail(mode ? "pixel inside the fog circle differs" : "fog shown while off", x, y);
                    if (mode && inside) begin
                        clear_seen = clear_seen + 1;
                        if (d2 > (R - 1) * (R - 1)) edge_in = edge_in + 1;
                    end
                end else begin
                    if ({r_f, g_f, b_f} !== 12'h000)
                        fail("pixel outside the fog circle not black", x, y);
                    if ({r_n, g_n, b_n} === 12'h000) black_ref = black_ref + 1;
                    else dark_seen = dark_seen + 1;
                    if (d2 <= (R + 1) * (R + 1)) edge_out = edge_out + 1;
                end
            end
        end
    endtask

    task check_frame;
        integer y;
        begin
            for (y = 0; y < 480; y = y + 1) check_line(y, 1);
        end
    endtask

    integer y;
    initial begin
        checked = 0; clear_seen = 0; dark_seen = 0; edge_in = 0; edge_out = 0;
        ball_seen = 0; black_ref = 0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        // Fog off: identical pictures.
        new_frame(12'd0, -18'sd25600, -18'sd12800);       // ball at (220, 190) on screen
        for (y = 150; y < 240; y = y + 7) check_line(y, 0);

        // fog_en rising mid-frame must not change this picture.
        fog_en = 1'b1;
        for (y = 160; y < 230; y = y + 9) check_line(y, 0);

        // From the next frame on, every pixel follows the model.
        new_frame(12'd0, -18'sd25600, -18'sd12800);
        if (ball_sx !== 11'sd220 || ball_sy !== 11'sd190) fail("ball screen position", ball_sx, ball_sy);
        check_frame();

        // 45 degrees, ball over a box: the circle and the boxes turn together.
        new_frame(12'd512, (5 * 16 + 8 - 168) * 256, (5 * 16 + 8 - 168) * 256);
        check_frame();

        // Circle clipped by the top-left of the screen (negative dx/dy rows).
        new_frame(12'd0, -18'sd75000, -18'sd59000);
        check_frame();

        // fog_en falling mid-frame keeps the fog until the next frame.
        fog_en = 1'b0;
        for (y = 0; y < 100; y = y + 11) check_line(y, 1);
        new_frame(12'd0, -18'sd75000, -18'sd59000);
        for (y = 0; y < 480; y = y + 13) check_line(y, 0);

        if (dark_seen < 100000 || clear_seen < 15000 || edge_in < 300 || edge_out < 300 || ball_seen < 100) begin
            $display("FAIL fog render: coverage too low: fogged=%0d clear=%0d edge_in=%0d edge_out=%0d ball=%0d",
                     dark_seen, clear_seen, edge_in, edge_out, ball_seen);
            $finish;
        end
        $display("PASS: fog render circle radius %0d at 0 and 45 degrees and clipped, frame-latched on/off; %0d pixels, %0d clear, %0d fogged, %0d/%0d on the edge",
                 R, checked, clear_seen, dark_seen, edge_in, edge_out);
        $finish;
    end
endmodule
