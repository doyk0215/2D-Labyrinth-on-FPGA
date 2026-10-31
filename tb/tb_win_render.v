`timescale 1ns / 1ps

// Pixel-level checks against a row-bitmap model independent of font_rom's
// column ROM. A full VGA raster includes blanking and one-clock sync checks.
module tb_win_render;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, ce_pix = 1'b0, frame_tick = 1'b0;
    reg [1:0] game_state = 2'b10;
    reg [9:0] pixel_x = 0, pixel_y = 0;
    reg active_video = 1'b1, hs = 1'b1, vs = 1'b1, ball_on = 1'b1;
    wire [3:0] r, g, b;
    wire vga_hs, vga_vs;
    render dut (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(game_state), .n_cells(4'd10), .angle(12'd0), .sin_q(16'sd0), .cos_q(16'sd16384),
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
            @(negedge clk); frame_tick = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask
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

    integer x, y, image_file, text_pixels = 0, checked = 0;
    reg panel, accent;
    reg [11:0] expected;
    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        pixel_x = 156; pixel_y = 212;
        check_colour(12'hfc0); // ball remains unchanged in PLAY
        game_state = 2'b11;
        check_colour(12'hfc0); // WIN does not appear mid-frame
        capture_frame();
        check_colour(12'hfff); // text takes priority over the ball
        repeat (3) begin capture_frame(); check_colour(12'hfff); end
        game_state = 2'b10;
        check_colour(12'hfff); // WIN does not disappear mid-frame
        capture_frame();
        check_colour(12'hfc0);
        game_state = 2'b11;
        capture_frame();
        ball_on = 1'b0;
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
                panel = x >= 132 && x < 508 && y >= 192 && y < 288;
                accent = (panel && (x < 136 || x >= 504 || y < 196 || y >= 284)) ||
                         (x >= 12 && x < 628 && y >= 12 && y < 468 &&
                          (x < 16 || x >= 624 || y < 16 || y >= 464));
                if (!active_video) begin
                    if ({r,g,b} !== 12'h000) fail("RGB leaked into blanking");
                end else if (panel || accent) begin
                    expected = expected_text(x,y) ? 12'hfff : accent ? 12'h0f0 : 12'h013;
                    if ({r,g,b} !== expected) fail("glyph, border, or pixel latency mismatch");
                    if (expected_text(x,y)) text_pixels = text_pixels + 1;
                end
                if (vga_hs !== hs || vga_vs !== vs) fail("sync latency changed");
                if (active_video) $fwrite(image_file, "%c%c%c", {r,r}, {g,g}, {b,b});
                checked = checked + 1;
            end
        end
        $fclose(image_file);
        if (text_pixels == 0) fail("message had no foreground pixels");
        @(negedge clk); rst = 1'b1; active_video = 1'b1; pixel_x = 156; pixel_y = 212;
        check_colour(12'h000);
        rst = 1'b0; game_state = 2'b10; ball_on = 1'b1;
        check_colour(12'hfc0); // reset clears a stale WIN without another frame
        $display("PASS: win render YOU WIN glyphs, frame latching, priority, reset, blanking and sync; %0d pixels checked", checked);
        $finish;
    end
    initial begin #10000000; fail("timeout"); end
endmodule
