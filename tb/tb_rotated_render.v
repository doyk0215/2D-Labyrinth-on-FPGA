`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Independent real-number inverse mapping for the affine renderer. This uses
// the fixed maze RAM, rather than copying the RTL's incremental arithmetic.
module tb_rotated_render;
    localparam real PI = 3.14159265358979323846;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg ce_pix = 1'b0;
    reg frame_tick = 1'b0;
    reg [11:0] angle = 12'd0;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] pixel_y = 10'd0;
    reg active_video = 1'b0;
    reg hsync_in = 1'b1;
    reg vsync_in = 1'b1;
    wire signed [15:0] sin_q, cos_q;
    wire [9:0] maze_raddr;
    wire maze_rdata;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;

    always #5 clk = ~clk;

    sincos_rom trig_i (.clk(clk), .angle(angle), .sin_q(sin_q), .cos_q(cos_q));
    maze_ram ram_i (
        .clk(clk), .we(1'b0), .waddr(10'd0), .wdata(1'b0),
        .raddr_p(10'd0), .rdata_p(), .ren_r(1'b1), .raddr_r(maze_raddr),
        .rdata_r(maze_rdata)
    );
    render dut (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(`ST_PLAY), .n_cells(4'd10), .cam_x(18'sd0), .cam_y(18'sd0), .time_min_bcd(8'h00), .time_sec_bcd(8'h00),
        .angle(angle), .sin_q(sin_q), .cos_q(cos_q),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .hsync_in(hsync_in), .vsync_in(vsync_in),
        .maze_raddr(maze_raddr), .maze_rdata(maze_rdata),
        .start_col(5'd1), .start_row(5'd1),
        .goal_col(5'd1), .goal_row(5'd19),
        // Item boxes (Story 9.1): buff 0 at tile (5,5), buff 1 at (9,13) but
        // hidden by box_visible, debuff 2 at (15,9), debuff 3 at (13,15) but
        // not valid. Only boxes 0 and 2 may be drawn.
        .box_cols({5'd13, 5'd15, 5'd9, 5'd5}), .box_rows({5'd15, 5'd9, 5'd13, 5'd5}),
        .box_valid(4'b0111), .box_visible(4'b1101),
        .ball_on(1'b0),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs)
    );

    integer checked = 0, box_checked = 0;
    real model_sin, model_cos;

    // Independent model of the 16 x 16 item-box tile (spec Design Notes):
    // margin at 0/15 shows the tile underneath, outline at 1/14, a white "?"
    // in columns 5-10 of rows 3-11, fill elsewhere.
    function [11:0] box_pixel;
        input buff;
        input integer lx, ly;
        input [11:0] under;
        reg [5:0] g;
        begin
            case (ly)
                3: g = 6'b011110;  4: g = 6'b110011;  5: g = 6'b000011;
                6: g = 6'b000110;  7, 8, 10, 11: g = 6'b001100;
                default: g = 6'b000000;
            endcase
            if (lx == 0 || lx == 15 || ly == 0 || ly == 15)
                box_pixel = under;
            else if (lx >= 5 && lx <= 10 && g[10 - lx])
                box_pixel = 12'hfff;
            else if (lx == 1 || lx == 14 || ly == 1 || ly == 14)
                box_pixel = buff ? 12'h0f0 : 12'hf88;
            else
                box_pixel = buff ? 12'h04f : 12'hc00;
        end
    endfunction

    task fail;
        input [255:0] reason;
        input integer x;
        input integer y;
        begin
            $display("FAIL rotated render: %0s at angle=%0d pixel=(%0d,%0d)",
                     reason, dut.angle_snap, x, y);
            $finish;
        end
    endtask

    task capture_angle;
        input [11:0] new_angle;
        real theta, extent;
        begin
            @(negedge clk);
            ce_pix = 1'b0;
            angle = new_angle;
            repeat (3) @(posedge clk);
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            if (dut.angle_snap !== new_angle)
                fail("angle snapshot was not captured", -1, -1);
            theta = 2.0 * PI * new_angle / 4096.0;
            model_sin = $sin(theta);
            model_cos = $cos(theta);
            extent = 168.0 * (($sin(theta) < 0.0 ? -$sin(theta) : $sin(theta)) +
                              ($cos(theta) < 0.0 ? -$cos(theta) : $cos(theta)));
            if (extent >= 240.0)
                fail("rotated map does not fit within 480 visible lines", -1, -1);
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
            // The final pixel of the previous scanline seeds x=0 for this y.
            // Real timing holds pixel_y for a whole line; hold it here for a
            // few clocks too, so the renderer's registered row products settle.
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
                hsync_in = 1'b1;
                vsync_in = 1'b1;
                qx = dut.walk_x_q;
                qy = dut.walk_y_q;
                check_color = 1'b0;
                expected = 12'h002;

                if ((x % stride) == 0 || x == 320) begin
                    mx = 168.0 + (x - 320.0) * model_cos +
                         (y - 240.0) * model_sin;
                    my = 168.0 - (x - 320.0) * model_sin +
                         (y - 240.0) * model_cos;
                    ex = qx / 16384.0 - mx;
                    ey = qy / 16384.0 - my;
                    if (ex < 0.0) ex = -ex;
                    if (ey < 0.0) ey = -ey;
                    if (ex > 1.0 || ey > 1.0)
                        fail("affine coordinate differs by over one pixel", x, y);

                    // At zero degrees, check every sampled pixel, including
                    // all exact tile/map edges. At other angles omit samples
                    // within one pixel of a nearest-neighbour boundary.
                    if (dut.angle_snap == 12'd0) begin
                        check_color = 1'b1;
                        if (x >= 152 && x < 488 && y >= 72 && y < 408) begin
                            tile_x = (x - 152) / 16;
                            tile_y = (y - 72) / 16;
                        end else begin
                            tile_x = -1;
                            tile_y = -1;
                        end
                    end else if (mx > 1.0 && mx < 335.0 &&
                                 my > 1.0 && my < 335.0) begin
                        tile_x = $rtoi($floor(mx / 16.0));
                        tile_y = $rtoi($floor(my / 16.0));
                        fx = mx - 16.0 * tile_x;
                        fy = my - 16.0 * tile_y;
                        if (fx > 1.0 && fx < 15.0 && fy > 1.0 && fy < 15.0)
                            check_color = 1'b1;
                    end else if (mx < -1.0 || mx > 337.0 ||
                                 my < -1.0 || my > 337.0) begin
                        tile_x = -1;
                        tile_y = -1;
                        check_color = 1'b1;
                    end

                    if (check_color && tile_x >= 0 && tile_y >= 0) begin
                        if (tile_x == 1 && tile_y == 1)
                            expected = 12'hf00; // red start
                        else if (tile_x == 1 && tile_y == 19)
                            expected = 12'h0f0; // green goal
                        else if (ram_i.tile_mem[tile_y * `MAP_STRIDE + tile_x])
                            expected = 12'hfff;
                        else
                            expected = 12'h346;
                        // The box mask is looked up at the renderer's own
                        // sample point (checked against the model above), so
                        // it is exact at every angle.
                        if ((tile_x == 5 && tile_y == 5) || (tile_x == 15 && tile_y == 9)) begin
                            expected = box_pixel(tile_x == 5, qx[17:14], qy[17:14], expected);
                            box_checked = box_checked + 1;
                        end
                    end
                end

                @(posedge clk); #1;
                if (vga_hs !== 1'b1 || vga_vs !== 1'b1)
                    fail("sync pipeline misaligned", x, y);
                if (check_color) begin
                    checked = checked + 1;
                    if ({vga_r, vga_g, vga_b} !== expected) begin
                        $display("  RGB=%h expected=%h model=(%f,%f)",
                                 {vga_r, vga_g, vga_b}, expected, mx, my);
                        fail("wrong maze color", x, y);
                    end
                end
            end
        end
    endtask

    integer y;
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        capture_angle(12'd0);
        for (y = 0; y < 480; y = y + 4) check_line(y, 1);
        check_line(71, 1);
        check_line(72, 1);
        check_line(407, 1);
        check_line(408, 1);
        // Every scanline through the two drawn boxes, so each mask row is seen.
        for (y = 152; y < 168; y = y + 1) check_line(y, 1);   // buff box, tile row 5
        for (y = 216; y < 232; y = y + 1) check_line(y, 1);   // debuff box, tile row 9

        capture_angle(12'd512); // 45 degrees
        for (y = 0; y < 480; y = y + 16) check_line(y, 7);
        // The live ROM may change between frames, but the raster must not.
        @(negedge clk); ce_pix = 1'b0; angle = 12'd1024;
        repeat (4) @(posedge clk);
        if (dut.angle_snap !== 12'd512) fail("angle changed mid-frame", -1, -1);
        check_line(240, 7);

        capture_angle(12'd1024); // 90 degrees
        for (y = 0; y < 480; y = y + 16) check_line(y, 7);
        // At 90 degrees the boxes turn with the map: check every line of the
        // map at full density, so the turned "?" is seen pixel by pixel.
        for (y = 72; y < 408; y = y + 1) check_line(y, 1);
        capture_angle(12'd1536); // 135 degrees
        for (y = 0; y < 480; y = y + 16) check_line(y, 7);

        if (box_checked < 900) fail("too few item-box pixels checked", box_checked, -1);
        $display("PASS: rotated renderer at 0, 45, 90, 135 degrees; %0d pixels checked, %0d on item boxes", checked, box_checked);
        $finish;
    end
endmodule
