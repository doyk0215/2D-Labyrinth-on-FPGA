`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 7.3 on the real top at N = 15 (legacy start, sw[4:0] = 15): the ball
// is searched for in the VGA stream of whole frames and must sit at the
// rotation of (ball - camera) about the screen centre; the maze coordinate
// the renderer uses under the drawn ball must be the ball's position; the
// first PLAY frame shows the ball at the screen centre (the camera snapped);
// and the camera, the scanline base and the ball's screen position never
// change during active video. A forced ball path then makes the camera follow.
module tb_top_story73_camera;
    reg clk = 1'b0;
    reg btnL = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;

    pullup (ps2_clk);
    pullup (ps2_data);
    always #5 clk = ~clk;

    My_Top_Module #(.START_IN_MENU(1'b0)) dut (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnL(btnL), .btnR(1'b0), .btnD(1'b0),
        .sw(16'h400F), .led(led), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    localparam real PI = 3.14159265358979323846;
    localparam real CENTRE = 248.0;                      // N = 15 map centre, maze pixels
    integer errors = 0;

    task fail;
        input [511:0] msg;
        begin errors = errors + 1; if (errors <= 20) $display("FAIL Story 7.3 top: %0s", msg); end
    endtask

    // ---- drawn-ball statistics for the frame in progress ----
    reg [9:0] px_d, py_d;
    integer n_clk, sum_x, sum_y;
    wire is_ball = (vga_r == 4'hf) && (vga_g == 4'hc) && (vga_b == 4'h0);
    always @(posedge clk) begin
        px_d <= dut.pixel_x; py_d <= dut.pixel_y;      // vga_* lag pixel_x/y by one clock
        if (is_ball) begin n_clk = n_clk + 1; sum_x = sum_x + px_d; sum_y = sum_y + py_d; end
    end

    // ---- no tearing: nothing the picture depends on moves in active video ----
    reg signed [17:0] cam_x_p, cam_y_p;
    reg signed [26:0] base_x_p, base_y_p;
    reg signed [10:0] sx_p, sy_p;
    integer tears = 0;
    reg armed = 1'b0;                                     // from the first PLAY frame on
    always @(posedge clk) begin
        if (dut.phys_init) armed <= 1'b1;
        if (armed && dut.active_video &&
            (dut.cam_x !== cam_x_p || dut.cam_y !== cam_y_p ||
             dut.render_i.base_x_q !== base_x_p || dut.render_i.base_y_q !== base_y_p ||
             dut.ball_sx !== sx_p || dut.ball_sy !== sy_p))
            tears = tears + 1;
        cam_x_p <= dut.cam_x; cam_y_p <= dut.cam_y;
        base_x_p <= dut.render_i.base_x_q; base_y_p <= dut.render_i.base_y_q;
        sx_p <= dut.ball_sx; sy_p <= dut.ball_sy;
    end

    // ---- the maze coordinate render uses at one chosen pixel ----
    integer probe_x = -1, probe_y = -1;
    reg probe_hit = 1'b0;
    reg signed [26:0] probe_wx, probe_wy;
    always @(posedge clk)
        if (dut.pixel_x == probe_x && dut.pixel_y == probe_y && dut.active_video) begin
            probe_wx <= dut.render_i.walk_x_q; probe_wy <= dut.render_i.walk_y_q; probe_hit <= 1'b1;
        end

    // Measure one whole frame from the frame_tick that follows `start`.
    real cx, cy, ex, ey, th, rx, ry, wx, wy, bxp, byp;
    task measure;
        input integer label;
        input integer expect_centre;
        reg [8*80-1:0] tag;
        begin
            @(posedge dut.frame_tick);
            repeat (60) @(posedge clk);                 // physics, camera and overlay settle in blanking
            th = 2.0 * PI * dut.angle / 4096.0;
            bxp = dut.ball_x / 256.0; byp = dut.ball_y / 256.0;
            rx = bxp - dut.cam_x / 256.0; ry = byp - dut.cam_y / 256.0;
            ex = 320.0 + rx * $cos(th) - ry * $sin(th);
            ey = 240.0 + rx * $sin(th) + ry * $cos(th);
            probe_x = $rtoi(ex + 0.5); probe_y = $rtoi(ey + 0.5); probe_hit = 1'b0;
            n_clk = 0; sum_x = 0; sum_y = 0;
            @(posedge dut.frame_tick);
            $sformat(tag, "frame %0d", label);
            if (n_clk != 81 * 4) begin
                $display("  %0s: ball covers %0d pixel-clocks", tag, n_clk);
                fail("drawn ball is not a whole 81-pixel disc");
            end else begin
                cx = 1.0 * sum_x / n_clk; cy = 1.0 * sum_y / n_clk;
                $display("%0s: angle=%0d ball=(%f,%f) cam=(%f,%f) drawn=(%f,%f) model=(%f,%f)",
                         tag, dut.angle, bxp, byp, dut.cam_x / 256.0, dut.cam_y / 256.0, cx, cy, ex, ey);
                if (cx - ex > 1.0 || ex - cx > 1.0 || cy - ey > 1.0 || ey - cy > 1.0)
                    fail("drawn ball differs from the rotation of ball - camera");
                if (expect_centre && (cx - 320.0 > 0.5 || 320.0 - cx > 0.5 || cy - 240.0 > 0.5 || 240.0 - cy > 0.5))
                    fail("first PLAY frame does not show the ball at the screen centre");
            end
            if (!probe_hit) fail("probe pixel under the ball was not drawn");
            else begin
                wx = probe_wx / 16384.0 - CENTRE; wy = probe_wy / 16384.0 - CENTRE;
                if (wx - bxp > 1.5 || bxp - wx > 1.5 || wy - byp > 1.5 || byp - wy > 1.5) begin
                    $display("  maze under the drawn ball (%f,%f), ball (%f,%f)", wx, wy, bxp, byp);
                    fail("the maze under the drawn ball is not where the ball is");
                end
            end
        end
    endtask

    integer i, moved_x, moved_y;
    reg signed [17:0] fx, fy;
    initial begin
        n_clk = 0; sum_x = 0; sum_y = 0;
        // first PLAY frame: phys_init comes on a frame_tick; measure that frame
        @(posedge dut.phys_init);
        if (dut.n_cells !== 4'd15) fail("bench is not running N = 15");
        repeat (60) @(posedge clk);
        if (dut.cam_x !== dut.ball_x || dut.cam_y !== dut.ball_y) fail("camera did not snap to the spawn");
        th = 2.0 * PI * dut.angle / 4096.0;
        n_clk = 0; sum_x = 0; sum_y = 0;
        bxp = dut.ball_x / 256.0; byp = dut.ball_y / 256.0;
        @(posedge dut.frame_tick);
        if (n_clk != 81 * 4) begin
            $display("  first PLAY frame: ball covers %0d pixel-clocks", n_clk);
            fail("first PLAY frame does not draw the whole ball");
        end else begin
            cx = 1.0 * sum_x / n_clk; cy = 1.0 * sum_y / n_clk;
            $display("first PLAY frame: ball=(%f,%f) drawn=(%f,%f)", bxp, byp, cx, cy);
            if (cx - 320.0 > 0.5 || 320.0 - cx > 0.5 || cy - 240.0 > 0.5 || 240.0 - cy > 0.5)
                fail("first PLAY frame does not show the ball at the screen centre");
        end

        // falling in the start cell, then rotating
        measure(1, 0);
        btnL = 1'b1;
        repeat (4) @(posedge dut.frame_tick);
        measure(2, 0);
        btnL = 1'b0;

        // A forced ball path, 5 px/frame to the left only, leaves the 48 px
        // dead zone after about 10 frames. The camera must follow on x, not
        // move on y, and keep the ball within the dead zone plus lag; cam_x
        // and cam_y then differ by tens of pixels, so a swapped axis in the
        // overlay or render would show in measure(3).
        moved_x = dut.cam_x; moved_y = dut.cam_y;
        fx = dut.ball_x; fy = dut.ball_y;
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge dut.frame_tick);
            fx = fx - 18'sd1280;
            force dut.ball_x = fx; force dut.ball_y = fy;
        end
        measure(3, 0);
        $display("camera moved from (%f,%f) to (%f,%f)", moved_x / 256.0, moved_y / 256.0,
                 dut.cam_x / 256.0, dut.cam_y / 256.0);
        if (dut.cam_x >= moved_x - 20 * 256) fail("camera did not follow the forced ball to the left");
        if (dut.cam_y !== moved_y) fail("camera moved on y although the ball did not");
        if (dut.ball_x - dut.cam_x < -88 * 256 || dut.ball_x - dut.cam_x > 88 * 256)
            fail("ball left the dead zone plus smoothing lag");
        release dut.ball_x; release dut.ball_y;

        if (tears != 0) begin $display("  %0d clocks changed in active video", tears); fail("picture inputs changed during active video"); end
        if (errors == 0)
            $display("PASS: Story 7.3 top camera - ball drawn at ball - camera, maze aligned under it, snapped first frame, follows, no tearing");
        else
            $display("FAIL Story 7.3 top: %0d errors", errors);
        $finish;
    end
endmodule
