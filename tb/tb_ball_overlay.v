`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for ball_overlay (Story 3.1): the ball's screen
// position against a real-number model, and the shape of the drawn disc.
module tb_ball_overlay;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg signed [17:0] ball_x = 0, ball_y = 0;
    reg signed [17:0] cam_x = 0, cam_y = 0;       // camera (Story 7.3): the ball is drawn relative to it
    real cam_px_x = 0.0, cam_px_y = 0.0;
    reg signed [15:0] sin_q = 0, cos_q = 16384;
    reg [9:0] pixel_x = 0, pixel_y = 0;
    reg active_video = 1'b1;
    wire signed [10:0] ball_sx, ball_sy;
    wire ball_on;

    always #5 clk = ~clk;

    ball_overlay dut (
        .clk(clk), .rst(rst), .start(start), .ball_x(ball_x), .ball_y(ball_y), .cam_x(cam_x), .cam_y(cam_y),
        .sin_q(sin_q), .cos_q(cos_q), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .ball_sx(ball_sx), .ball_sy(ball_sy), .ball_on(ball_on)
    );

    localparam real PI = 3.14159265358979323846;
    integer errors = 0;

    function near_ok;                    // hardware value v matches model value m
        input real m;
        input integer v;
        real f;
        integer r;
        begin
            r = $rtoi($floor(m + 0.5));
            f = m + 0.5 - $floor(m + 0.5);      // fractional part after the rounding shift
            near_ok = (v == r) || ((f < 0.02 || f > 0.98) && (v == r - 1 || v == r + 1));
        end
    endfunction

    task place;      // maze position in px (from the map centre), angle in 4096 steps
        input real mx, my;
        input integer a;
        real th, ex, ey;
        begin
            th = 2.0 * PI * a / 4096.0;
            ball_x = $rtoi($floor(mx * 256.0 + 0.5)); ball_y = $rtoi($floor(my * 256.0 + 0.5));
            sin_q = $rtoi($floor(16384.0 * $sin(th) + 0.5));
            cos_q = $rtoi($floor(16384.0 * $cos(th) + 0.5));
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            repeat (6) @(posedge clk);
            // screen offset = (maze - camera) rotated by the angle (render.v's inverse mapping)
            ex = 320.0 + (mx - cam_px_x) * $cos(th) - (my - cam_px_y) * $sin(th);
            ey = 240.0 + (mx - cam_px_x) * $sin(th) + (my - cam_px_y) * $cos(th);
            // exact, except where the model value sits within 0.02 px of a rounding boundary
            if (!near_ok(ex, ball_sx) || !near_ok(ey, ball_sy)) begin
                errors = errors + 1;
                $display("FAIL: maze (%f,%f) angle %0d -> screen (%0d,%0d), model (%f,%f)", mx, my, a, ball_sx, ball_sy, ex, ey);
            end
        end
    endtask

    task set_cam;    // camera in px from the map centre, rounded to Q9.8 as the hardware holds it
        input real cx, cy;
        begin
            cam_x = $rtoi($floor(cx * 256.0 + 0.5)); cam_y = $rtoi($floor(cy * 256.0 + 0.5));
            cam_px_x = cam_x / 256.0; cam_px_y = cam_y / 256.0;
        end
    endtask

    // Count the pixels flagged as ball in a window around the ball; check the shape.
    integer cnt, sym_err, dx, dy, expected;
    reg [24:0] seen [0:20];    // seen[dy+10][dx+10]
    task scan;
        begin
            cnt = 0; sym_err = 0;
            for (dy = -10; dy <= 10; dy = dy + 1) begin
                for (dx = -10; dx <= 10; dx = dx + 1) begin
                    pixel_x = ball_sx + dx; pixel_y = ball_sy + dy;
                    @(posedge clk); @(posedge clk); #1;      // ball_on is one clock behind the pixel
                    seen[dy + 10][dx + 10] = ball_on;
                    expected = (dx * dx + dy * dy <= `BALL_RADIUS * `BALL_RADIUS);
                    if (ball_on !== expected[0]) begin
                        errors = errors + 1;
                        if (errors < 10) $display("FAIL: pixel offset (%0d,%0d) ball_on=%b, expected %0d", dx, dy, ball_on, expected);
                    end
                    cnt = cnt + ball_on;
                end
            end
        end
    endtask

    integer k, model_count;
    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // positions: map centre, corners of the start/goal, several angles
        place(  0.0,   0.0,    0);
        place( 16.0,  16.0,    0);
        place(-144.0, 144.0,   0);
        place(  0.0,   0.0, 1500);
        place( 16.0,  16.0, 1024);     // 90 degrees clockwise: maze +x points down the screen
        place(-100.0, 60.5,  333);
        place( 120.0, -75.0, 2048);
        place(  3.25, -163.0, 3071);
        place(163.0, 163.0,  2561);

        // Story 7.3: a camera with clearly different x and y, so a swapped or
        // shared camera axis moves the ball by tens of pixels
        set_cam(30.0, 70.0);
        place(100.0, -50.0,    0);
        place(100.0, -50.0, 1024);
        place(100.0, -50.0,  333);
        set_cam(-137.37, 91.5);
        place(-120.25, 60.0, 2900);
        place(-200.0, 150.0, 512);
        set_cam(0.0, 0.0);

        // the disc: expected number of pixels with dx^2 + dy^2 <= R^2
        model_count = 0;
        for (dy = -`BALL_RADIUS; dy <= `BALL_RADIUS; dy = dy + 1)
            for (dx = -`BALL_RADIUS; dx <= `BALL_RADIUS; dx = dx + 1)
                if (dx * dx + dy * dy <= `BALL_RADIUS * `BALL_RADIUS) model_count = model_count + 1;
        place(10.0, -20.0, 700);
        scan;
        if (cnt != model_count) begin errors = errors + 1; $display("FAIL: disc has %0d pixels, expected %0d", cnt, model_count); end

        // nothing is drawn outside the visible area
        active_video = 1'b0;
        pixel_x = ball_sx; pixel_y = ball_sy;
        repeat (3) @(posedge clk); #1;
        if (ball_on !== 1'b0) begin errors = errors + 1; $display("FAIL: ball drawn while active_video = 0"); end
        active_video = 1'b1;

        $display("disc size %0d pixels", cnt);
        if (errors == 0) $display("PASS: ball_overlay - screen position and a round disc of radius %0d", `BALL_RADIUS);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
