`timescale 1ns / 1ps

module tb_vga_timing;

    reg clk = 1'b0;
    reg rst = 1'b1;
    wire ce_pix;
    wire frame_tick;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;
    wire hsync;
    wire vsync;
    wire [15:0] pattern_led;
    wire [3:0] pattern_r;
    wire [3:0] pattern_g;
    wire [3:0] pattern_b;
    wire pattern_hs;
    wire pattern_vs;
    wire pattern_ps2_clk;
    wire pattern_ps2_data;
    wire pattern_oled_cs;
    wire pattern_oled_mosi;
    wire pattern_oled_sclk;
    wire pattern_oled_dc;
    wire pattern_oled_res;
    wire pattern_oled_vbatc;
    wire pattern_oled_vddc;
    reg [3:0] expected_r;
    reg [3:0] expected_g;
    reg [3:0] expected_b;

    integer expected_x;
    integer expected_y;
    integer checked_pixels;
    integer frame_ticks;
    integer hsync_low_pixels;
    integer vsync_low_pixels;
    integer active_pixels;
    time last_ce_time;
    reg saw_ce;

    always #5 clk = ~clk;

    vga_timing dut (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync        (hsync),
        .vsync        (vsync)
    );

    top pattern_dut (
        .clk        (clk),
        .btnC       (rst),
        .btnU       (1'b0),
        .btnL       (1'b0),
        .btnR       (1'b0),
        .btnD       (1'b0),
        .sw         (16'h0000),
        .led        (pattern_led),
        .vga_r      (pattern_r),
        .vga_g      (pattern_g),
        .vga_b      (pattern_b),
        .vga_hs     (pattern_hs),
        .vga_vs     (pattern_vs),
        .ps2_clk    (pattern_ps2_clk),
        .ps2_data   (pattern_ps2_data),
        .oled_cs    (pattern_oled_cs),
        .oled_mosi  (pattern_oled_mosi),
        .oled_sclk  (pattern_oled_sclk),
        .oled_dc    (pattern_oled_dc),
        .oled_res   (pattern_oled_res),
        .oled_vbatc (pattern_oled_vbatc),
        .oled_vddc  (pattern_oled_vddc)
    );

    initial begin
        expected_x = 0;
        expected_y = 0;
        checked_pixels = 0;
        frame_ticks = 0;
        hsync_low_pixels = 0;
        vsync_low_pixels = 0;
        active_pixels = 0;
        saw_ce = 1'b0;
        expected_r = 4'h0;
        expected_g = 4'h0;
        expected_b = 4'h0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Check one complete 800x525 frame, one enabled pixel at a time.
        while (checked_pixels < 800 * 525) begin
            @(negedge clk);
            if (ce_pix) begin
                if (saw_ce && (($time - last_ce_time) != 40)) begin
                    $display("FAIL: ce_pix spacing was %0t ns, expected 40 ns", $time - last_ce_time);
                    $finish;
                end
                saw_ce = 1'b1;
                last_ce_time = $time;

                if ((pixel_x !== expected_x[9:0]) || (pixel_y !== expected_y[9:0])) begin
                    $display("FAIL: pixel coordinate got (%0d,%0d), expected (%0d,%0d)",
                             pixel_x, pixel_y, expected_x, expected_y);
                    $finish;
                end

                if (hsync !== !((expected_x >= 656) && (expected_x < 752))) begin
                    $display("FAIL: hsync level incorrect at (%0d,%0d)", expected_x, expected_y);
                    $finish;
                end
                if (vsync !== !((expected_y >= 490) && (expected_y < 492))) begin
                    $display("FAIL: vsync level incorrect at (%0d,%0d)", expected_x, expected_y);
                    $finish;
                end
                if (active_video !== ((expected_x < 640) && (expected_y < 480))) begin
                    $display("FAIL: active_video incorrect at (%0d,%0d)", expected_x, expected_y);
                    $finish;
                end
                if (frame_tick !== ((expected_x == 0) && (expected_y == 480))) begin
                    $display("FAIL: frame_tick incorrect at (%0d,%0d)", expected_x, expected_y);
                    $finish;
                end

                expected_r = 4'h0;
                expected_g = 4'h0;
                expected_b = 4'h0;
                if (expected_y < 480) begin
                    if (expected_x < 80) begin
                        expected_r = 4'hf; expected_g = 4'hf; expected_b = 4'hf;
                    end else if (expected_x < 160) begin
                        expected_r = 4'hf; expected_g = 4'hf;
                    end else if (expected_x < 240) begin
                        expected_g = 4'hf; expected_b = 4'hf;
                    end else if (expected_x < 320) begin
                        expected_g = 4'hf;
                    end else if (expected_x < 400) begin
                        expected_r = 4'hf; expected_b = 4'hf;
                    end else if (expected_x < 480) begin
                        expected_r = 4'hf;
                    end else if (expected_x < 560) begin
                        expected_b = 4'hf;
                    end
                end
                if ((pattern_r !== expected_r) || (pattern_g !== expected_g) ||
                    (pattern_b !== expected_b)) begin
                    $display("FAIL: colour bar at (%0d,%0d) got RGB %h%h%h expected %h%h%h",
                             expected_x, expected_y, pattern_r, pattern_g, pattern_b,
                             expected_r, expected_g, expected_b);
                    $finish;
                end

                if (!hsync) hsync_low_pixels = hsync_low_pixels + 1;
                if (!vsync) vsync_low_pixels = vsync_low_pixels + 1;
                if (active_video) active_pixels = active_pixels + 1;
                if (frame_tick) frame_ticks = frame_ticks + 1;

                checked_pixels = checked_pixels + 1;
                if (expected_x == 799) begin
                    expected_x = 0;
                    if (expected_y == 524)
                        expected_y = 0;
                    else
                        expected_y = expected_y + 1;
                end else begin
                    expected_x = expected_x + 1;
                end
            end
        end

        if (checked_pixels != 420000 || frame_ticks != 1 ||
            hsync_low_pixels != (96 * 525) ||
            vsync_low_pixels != (2 * 800) || active_pixels != (640 * 480)) begin
            $display("FAIL: totals pixels=%0d frame_tick=%0d hsync_low=%0d vsync_low=%0d active=%0d",
                     checked_pixels, frame_ticks, hsync_low_pixels,
                     vsync_low_pixels, active_pixels);
            $finish;
        end

        $display("PASS: 800x525 totals, active area, sync widths, 1-in-4 ce_pix, frame_tick, and all VGA colour bars");
        $finish;
    end

endmodule
