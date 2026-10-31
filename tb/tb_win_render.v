`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Pixel-level checks against a row-bitmap model independent of font_rom's
// column ROM. A full VGA raster includes blanking and one-clock sync checks.
module tb_win_render;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, ce_pix = 1'b0, frame_tick = 1'b0;
    reg [`GAME_STATE_W-1:0] game_state = `ST_PLAY;
    reg [9:0] pixel_x = 0, pixel_y = 0;
    reg active_video = 1'b1, hs = 1'b1, vs = 1'b1, ball_on = 1'b1;
    reg [7:0] tmin = 8'h00, tsec = 8'h00;
    reg [7:0] lat_min = 8'h00, lat_sec = 8'h00;
    localparam integer BLINK = 3;
    wire [3:0] r, g, b;
    wire vga_hs, vga_vs;
    render #(.BLINK_FRAMES(BLINK)) dut (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(game_state), .time_min_bcd(tmin), .time_sec_bcd(tsec), .angle(12'd0), .sin_q(16'sd0), .cos_q(16'sd16384),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .hsync_in(hs), .vsync_in(vs), .maze_raddr(), .maze_rdata(1'b1),
        .start_col(5'd19), .start_row(5'd19), .goal_col(5'd1), .goal_row(5'd1),
        .ball_on(ball_on), .vga_r(r), .vga_g(g), .vga_b(b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .sin_snap(), .cos_snap()
    );

    task fail;
        input [511:0] message;
        begin
            $display("FAIL win render: %0s at (%0d,%0d) RGB=%h", message, pixel_x, pixel_y, {r,g,b});
            $fatal(1);
        end
    endtask
    task capture_frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            lat_min = tmin; lat_sec = tsec; // the time is latched with the frame
            @(negedge clk); frame_tick = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask
    task goto_pixel;
        input integer px, py;
        begin
            pixel_x = px; pixel_y = py;
            repeat (3) @(negedge clk);
        end
    endtask
    // Sweep two scanlines so the renderer's row products settle, and keep the
    // colour of the goal tile's pixel (170,96): the goal is tile (1,1), which
    // covers maze pixels 16..31 and so screen x 168..183, y 88..103 at angle 0.
    reg [11:0] goal_rgb;
    task sample_goal;
        integer sx, sy;
        begin
            ce_pix = 1'b1;
            for (sy = 95; sy <= 96; sy = sy + 1) begin
                for (sx = 0; sx < 800; sx = sx + 1) begin
                    @(negedge clk);
                    pixel_x = sx; pixel_y = sy; active_video = (sx < 640);
                    @(posedge clk); #1;
                    if (sx == 170 && sy == 96) goal_rgb = {r,g,b};
                end
            end
            active_video = 1'b1;
        end
    endtask
    // One 5x7 column byte (bit 0 is the top row), written out independently
    // of font_rom's table.
    function [7:0] model_col;
        input [7:0] c;
        input integer col;
        reg [39:0] cols;
        begin
            case (c)
                "T": cols = {8'h01,8'h01,8'h7F,8'h01,8'h01};
                "I": cols = {8'h00,8'h41,8'h7F,8'h41,8'h00};
                "M": cols = {8'h7F,8'h02,8'h0C,8'h02,8'h7F};
                "E": cols = {8'h7F,8'h49,8'h49,8'h49,8'h41};
                ":": cols = {8'h00,8'h36,8'h36,8'h00,8'h00};
                "0": cols = {8'h3E,8'h51,8'h49,8'h45,8'h3E};
                "1": cols = {8'h00,8'h42,8'h7F,8'h40,8'h00};
                "2": cols = {8'h42,8'h61,8'h51,8'h49,8'h46};
                "3": cols = {8'h21,8'h41,8'h45,8'h4B,8'h31};
                "4": cols = {8'h18,8'h14,8'h12,8'h7F,8'h10};
                "5": cols = {8'h27,8'h45,8'h45,8'h45,8'h39};
                "6": cols = {8'h3C,8'h4A,8'h49,8'h49,8'h30};
                "7": cols = {8'h01,8'h71,8'h09,8'h05,8'h03};
                "8": cols = {8'h36,8'h49,8'h49,8'h49,8'h36};
                "9": cols = {8'h06,8'h49,8'h49,8'h29,8'h1E};
                default: cols = 40'h0;
            endcase
            model_col = cols >> ((4 - col) * 8);
        end
    endfunction
    function expected_time_text;
        input integer x, y;
        integer slot, column, row;
        reg [7:0] c;
        begin
            expected_time_text = 1'b0;
            if (x >= 160 && x < 480 && y >= 284 && y < 312) begin
                slot = (x - 160) / 32;
                column = ((x - 160) % 32) / 4;
                row = (y - 284) / 4;
                case (slot)
                    0: c = "T";
                    1: c = "I";
                    2: c = "M";
                    3: c = "E";
                    5: c = "0" + lat_min[7:4];
                    6: c = "0" + lat_min[3:0];
                    7: c = ":";
                    8: c = "0" + lat_sec[7:4];
                    9: c = "0" + lat_sec[3:0];
                    default: c = " ";
                endcase
                if (column < 5) expected_time_text = model_col(c, column) >> row & 1'b1;
            end
        end
    endfunction
    task check_colour;
        input [11:0] colour;
        begin
            @(posedge clk); #1;
            if ({r,g,b} !== colour) fail("unexpected panel colour or frame state");
            @(negedge clk);
        end
    endtask

    function expected_text;
        input integer x, y;
        integer cell_x, column, row;
        reg [34:0] rows;
        begin
            expected_text = 1'b0;
            if (x >= 156 && x < 484 && y >= 212 && y < 268) begin
                cell_x = (x - 156) / 48;
                column = ((x - 156) % 48) / 8;
                row = (y - 212) / 8;
                case (cell_x)
                    0: rows = {5'b10001,5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100}; // Y
                    1: rows = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110}; // O
                    2: rows = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110}; // U
                    4: rows = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010}; // W
                    5: rows = {5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110}; // I
                    6: rows = {5'b10001,5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001}; // N
                    default: rows = 35'b0;
                endcase
                if (column < 5) expected_text = rows[(6-row)*5 + 4-column];
            end
        end
    endfunction

    integer x, y, k, image_file, text_pixels = 0, time_pixels = 0, checked = 0;
    reg panel, accent;
    reg [11:0] expected;
    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        pixel_x = 156; pixel_y = 212;
        check_colour(12'hfc0); // ball remains unchanged in PLAY
        game_state = `ST_WIN;
        check_colour(12'hfc0); // WIN does not appear mid-frame
        capture_frame();
        check_colour(12'hfff); // text takes priority over the ball
        repeat (3) begin capture_frame(); check_colour(12'hfff); end
        game_state = `ST_PLAY;
        check_colour(12'hfff); // WIN does not disappear mid-frame
        capture_frame();
        check_colour(12'hfc0);

        // Time line: the value is latched with the frame, never mid-frame.
        // Cell 5 is the minutes tens digit and cell 6 the ones digit.
        tmin = 8'h01; tsec = 8'h23;
        game_state = `ST_WIN;
        capture_frame();
        goto_pixel(320, 288); check_colour(12'hfff); // '0': column 0, row 1 is lit
        goto_pixel(360, 288); check_colour(12'hfff); // '1': column 2, row 1 is lit
        tmin = 8'h02;
        check_colour(12'hfff);                       // still '1' until the next frame
        capture_frame();
        check_colour(12'h013);                       // '2': column 2, row 1 is empty
        tmin = 8'h01;

        // Goal blink: bright in PLAY, then bright for BLINK frames and dark
        // for BLINK frames, starting with the first WIN frame.
        ball_on = 1'b0;
        game_state = `ST_PLAY; capture_frame(); sample_goal();
        if (goal_rgb !== 12'h0f0) fail("goal tile is not plain green in PLAY");
        game_state = `ST_WIN;
        for (k = 0; k < 4 * BLINK; k = k + 1) begin
            capture_frame(); sample_goal();
            if (goal_rgb !== (((k / BLINK) % 2) ? 12'h030 : 12'h0f0))
                fail("goal blink phase does not match the frame count");
        end
        game_state = `ST_PLAY; capture_frame(); sample_goal();
        if (goal_rgb !== 12'h0f0) fail("goal tile still blinks after leaving WIN");
        goto_pixel(156, 212);

        tmin = 8'h12; tsec = 8'h34;
        game_state = `ST_WIN;
        capture_frame();
        ce_pix = 1'b1;
        image_file = $fopen("win_indication.ppm", "wb");
        if (!image_file) fail("could not create VGA preview");
        $fwrite(image_file, "P6\n640 480\n255\n");
        for (y = 0; y < 525; y = y + 1) begin
            for (x = 0; x < 800; x = x + 1) begin
                @(negedge clk);
                pixel_x = x; pixel_y = y;
                active_video = (x < 640 && y < 480);
                hs = !(x >= 656 && x < 752);
                vs = !(y >= 490 && y < 492);
                @(posedge clk); #1;
                panel = x >= 132 && x < 508 && y >= 192 && y < 324;
                accent = (panel && (x < 136 || x >= 504 || y < 196 || y >= 320)) ||
                         (x >= 12 && x < 628 && y >= 12 && y < 468 &&
                          (x < 16 || x >= 624 || y < 16 || y >= 464));
                if (!active_video) begin
                    if ({r,g,b} !== 12'h000) fail("RGB leaked into blanking");
                end else if (panel || accent) begin
                    expected = (expected_text(x,y) || expected_time_text(x,y)) ? 12'hfff :
                               accent ? 12'h0f0 : 12'h013;
                    if ({r,g,b} !== expected) fail("glyph, border, or pixel latency mismatch");
                    if (expected_text(x,y)) text_pixels = text_pixels + 1;
                    if (expected_time_text(x,y)) time_pixels = time_pixels + 1;
                end
                if (vga_hs !== hs || vga_vs !== vs) fail("sync latency changed");
                if (active_video) $fwrite(image_file, "%c%c%c", {r,r}, {g,g}, {b,b});
                checked = checked + 1;
            end
        end
        $fclose(image_file);
        if (text_pixels == 0) fail("message had no foreground pixels");
        if (time_pixels == 0) fail("time line had no foreground pixels");
        @(negedge clk); rst = 1'b1; active_video = 1'b1; pixel_x = 156; pixel_y = 212;
        check_colour(12'h000);
        rst = 1'b0; game_state = `ST_PLAY; ball_on = 1'b1;
        check_colour(12'hfc0); // reset clears a stale WIN without another frame
        $display("PASS: win render YOU WIN and TIME glyphs, goal blink, frame latching, priority, reset, blanking and sync; %0d pixels checked", checked);
        $finish;
    end
    initial begin #10000000; fail("timeout"); end
endmodule
