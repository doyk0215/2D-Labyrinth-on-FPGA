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

    initial begin
        expected_x = 0;
        expected_y = 0;
        checked_pixels = 0;
        frame_ticks = 0;
        hsync_low_pixels = 0;
        vsync_low_pixels = 0;
        active_pixels = 0;
        saw_ce = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Check every enabled pixel in one complete 800x525 frame.
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

        $display("PASS: 800x525 totals, 640x480 active area, sync widths, 1-in-4 ce_pix, and one frame_tick at vertical blank start");
        $finish;
    end

endmodule
