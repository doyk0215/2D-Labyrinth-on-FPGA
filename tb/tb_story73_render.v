`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 7.3: the N = 15 map drawn through the camera. An independent
// real-number inverse map (screen centre = map centre + camera) is compared
// with the renderer at 0, 45, 90 and 135 degrees, for the camera at the map
// centre and near each map edge. The bench has its own pseudo-random 32 x 32
// tile memory, so every tile of the 31 x 31 map is exercised.
module tb_story73_render;
    localparam real PI = 3.14159265358979323846;
    localparam real CENTRE = 248.0;              // N = 15: tile 15's centre, 16*15 + 8
    localparam real SIZE = 496.0;                // 31 tiles of 16 px
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg ce_pix = 1'b0;
    reg frame_tick = 1'b0;
    reg [11:0] angle = 12'd0;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] pixel_y = 10'd0;
    reg active_video = 1'b0;
    reg signed [`POS_W-1:0] cam_x = 0, cam_y = 0;
    wire signed [15:0] sin_q, cos_q;
    wire [9:0] maze_raddr;
    reg maze_rdata = 1'b0;
    wire [3:0] vga_r, vga_g, vga_b;

    always #5 clk = ~clk;

    reg tile_mem [0:`MAP_TILES-1];
    integer r, c;
    initial
        for (r = 0; r < 32; r = r + 1)
            for (c = 0; c < 32; c = c + 1)
                tile_mem[r * `MAP_STRIDE + c] = (r == 0 || c == 0 || r >= 30 || c >= 30) ? 1'b1 :
                                                (((r * 7 + c * 13 + r * c) % 5) == 0);
    always @(posedge clk) maze_rdata <= tile_mem[maze_raddr];   // maze_ram's one-clock read

    sincos_rom trig_i (.clk(clk), .angle(angle), .sin_q(sin_q), .cos_q(cos_q));
    render dut (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(`ST_PLAY), .n_cells(4'd15), .cam_x(cam_x), .cam_y(cam_y),
        .time_min_bcd(8'h00), .time_sec_bcd(8'h00),
        .angle(angle), .sin_q(sin_q), .cos_q(cos_q),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .hsync_in(1'b1), .vsync_in(1'b1),
        .maze_raddr(maze_raddr), .maze_rdata(maze_rdata),
        .start_col(5'd29), .start_row(5'd29),
        .goal_col(5'd1), .goal_row(5'd1), .ball_on(1'b0),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(), .vga_vs()
    );

    integer checked = 0, outside = 0, errors = 0;
    real model_sin, model_cos, cxp, cyp;

    task fail;
        input [255:0] reason;
        input integer x;
        input integer y;
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("FAIL Story 7.3 render: %0s at angle=%0d cam=(%0d,%0d) pixel=(%0d,%0d)",
                         reason, dut.angle_snap, cam_x, cam_y, x, y);
        end
    endtask

    // A frame: the camera moves, then the angle snapshot is taken (the order
    // does not matter to render, which reads the camera live).
    task set_view;
        input [11:0] new_angle;
        input integer cam_px_x, cam_px_y;
        real theta;
        begin
            @(negedge clk);
            ce_pix = 1'b0;
            angle = new_angle;
            cam_x = cam_px_x * 256; cam_y = cam_px_y * 256;
            cxp = cam_px_x; cyp = cam_px_y;
            repeat (3) @(posedge clk);
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (4) @(posedge clk);
            #1;
            if (dut.angle_snap !== new_angle) fail("angle snapshot was not captured", -1, -1);
            theta = 2.0 * PI * new_angle / 4096.0;
            model_sin = $sin(theta);
            model_cos = $cos(theta);
        end
    endtask

    task check_line;
        input integer y;
        input integer stride;
        integer x, tile_x, tile_y;
        reg [11:0] expected;
        reg check_color;
        reg signed [26:0] qx, qy;
        real mx, my, ex, ey, fx, fy;
        begin
            @(negedge clk);
            pixel_x = 10'd798;
            pixel_y = (y == 0) ? 10'd524 : y - 1;
            active_video = 1'b0;
            ce_pix = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            pixel_x = 10'd799;
            ce_pix = 1'b1;
            @(posedge clk); #1;

            for (x = 0; x < 640; x = x + 1) begin
                @(negedge clk);
                pixel_x = x;
                pixel_y = y;
                active_video = 1'b1;
                qx = dut.walk_x_q;
                qy = dut.walk_y_q;
                check_color = 1'b0;
                expected = 12'h002;

                if ((x % stride) == 0 || x == 320) begin
                    mx = CENTRE + cxp + (x - 320.0) * model_cos + (y - 240.0) * model_sin;
                    my = CENTRE + cyp - (x - 320.0) * model_sin + (y - 240.0) * model_cos;
                    ex = qx / 16384.0 - mx;
                    ey = qy / 16384.0 - my;
                    if (ex < 0.0) ex = -ex;
                    if (ey < 0.0) ey = -ey;
                    if (ex > 1.0 || ey > 1.0) fail("affine coordinate differs by over one pixel", x, y);

                    // Skip samples within one pixel of a tile or map boundary,
                    // except at 0 degrees, where the model is exact.
                    tile_x = -1; tile_y = -1;
                    if (mx >= 0.0 && mx < SIZE && my >= 0.0 && my < SIZE) begin
                        tile_x = $rtoi($floor(mx / 16.0));
                        tile_y = $rtoi($floor(my / 16.0));
                        fx = mx - 16.0 * tile_x;
                        fy = my - 16.0 * tile_y;
                        check_color = (dut.angle_snap == 12'd0) ||
                                      (fx > 1.0 && fx < 15.0 && fy > 1.0 && fy < 15.0);
                    end else begin
                        check_color = (dut.angle_snap == 12'd0) ||
                                      mx < -1.0 || mx > SIZE + 1.0 || my < -1.0 || my > SIZE + 1.0;
                    end

                    if (check_color) begin
                        if (tile_x < 0) begin
                            expected = 12'h002;              // background beyond the map
                        end else if (tile_x == 29 && tile_y == 29)
                            expected = 12'hf00;              // red start
                        else if (tile_x == 1 && tile_y == 1)
                            expected = 12'h0f0;              // green goal
                        else if (tile_mem[tile_y * `MAP_STRIDE + tile_x])
                            expected = 12'hfff;
                        else
                            expected = 12'h346;
                    end
                end

                @(posedge clk); #1;
                if (check_color) begin
                    checked = checked + 1;
                    if (expected == 12'h002) outside = outside + 1;
                    if ({vga_r, vga_g, vga_b} !== expected) begin
                        if (errors < 10)
                            $display("  RGB=%h expected=%h model=(%f,%f)", {vga_r, vga_g, vga_b}, expected, mx, my);
                        fail("wrong colour", x, y);
                    end
                end
            end
        end
    endtask

    // camera positions: map centre, then near each edge and corner
    integer cams [0:11];
    integer v, a, y;
    initial begin
        cams[0] = 0;    cams[1] = 0;
        cams[2] = 220;  cams[3] = 220;
        cams[4] = -220; cams[5] = -220;
        cams[6] = 220;  cams[7] = -220;
        cams[8] = -220; cams[9] = 0;
        cams[10] = 0;   cams[11] = 225;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        for (v = 0; v < 6; v = v + 1)
            for (a = 0; a < 4; a = a + 1) begin
                set_view(a * 512, cams[2 * v], cams[2 * v + 1]);
                if (a == 0)
                    for (y = 0; y < 480; y = y + 12) check_line(y, 1);
                else
                    for (y = 0; y < 480; y = y + 24) check_line(y, 7);
            end
        if (outside == 0) fail("no pixel beyond the map was checked", -1, -1);
        if (errors == 0)
            $display("PASS: Story 7.3 N=15 render through the camera at 0, 45, 90, 135 degrees; %0d pixels checked, %0d beyond the map", checked, outside);
        else
            $display("FAIL Story 7.3 render: %0d errors", errors);
        $finish;
    end
endmodule
