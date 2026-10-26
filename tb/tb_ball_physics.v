`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for ball_physics (Story 3.1).
// Gravity is checked against a real-number model, g*(sin, cos) with g = 64
// Q4.8 units (0.25 px/frame^2); position must follow the new velocity exactly.
module tb_ball_physics;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg phys_init = 1'b0;
    reg phys_en = 1'b1;
    reg [4:0] start_col = 5'd11, start_row = 5'd11;
    reg signed [15:0] sin_q = 16'sd0, cos_q = 16'sd16384;
    wire signed [17:0] ball_x, ball_y;
    wire signed [11:0] vel_x, vel_y;
    wire phys_done;

    always #5 clk = ~clk;

    ball_physics dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .phys_init(phys_init), .phys_en(phys_en),
        .start_col(start_col), .start_row(start_row), .sin_q(sin_q), .cos_q(cos_q),
        .ball_x(ball_x), .ball_y(ball_y), .vel_x(vel_x), .vel_y(vel_y), .phys_done(phys_done)
    );

    localparam real PI = 3.14159265358979323846;
    localparam integer CAP = 1792;
    localparam integer LIMIT = 163 * 256;
    integer errors = 0;
    integer done_count;
    always @(posedge clk) if (phys_done) done_count <= done_count + 1;

    task set_angle;                      // angle in 4096 steps = 360 degrees
        input integer a;
        real th;
        begin
            th = 2.0 * PI * a / 4096.0;
            sin_q = $rtoi($floor(16384.0 * $sin(th) + 0.5));
            cos_q = $rtoi($floor(16384.0 * $cos(th) + 0.5));
        end
    endtask

    // One frame: pulse frame_tick, wait for the update to finish.
    integer prev_vx, prev_vy, prev_px, prev_py, wait_n;
    task frame;
        begin
            prev_vx = vel_x; prev_vy = vel_y; prev_px = ball_x; prev_py = ball_y;
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            wait_n = 0;
            while (!phys_done && wait_n < 50) begin @(posedge clk); wait_n = wait_n + 1; end
            @(negedge clk);
            if (wait_n >= 50) begin errors = errors + 1; $display("FAIL: phys_done never came"); end
            repeat (10) @(posedge clk);
        end
    endtask

    // A frame while the game is not in PLAY: no update, no phys_done.
    task frame_idle;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (30) @(posedge clk);
        end
    endtask

    task do_init;
        input [4:0] c, r;
        begin
            start_col = c; start_row = r;
            @(negedge clk); phys_init = 1'b1;
            @(negedge clk); phys_init = 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    // Expected gravity step for the current sin/cos (real model, 64 * trig)
    function integer exp_gx; input integer dummy; begin exp_gx = $rtoi($floor(64.0 * sin_q / 16384.0 + 0.5)); end endfunction
    function integer exp_gy; input integer dummy; begin exp_gy = $rtoi($floor(64.0 * cos_q / 16384.0 + 0.5)); end endfunction
    function integer iabs; input integer v; begin iabs = (v < 0) ? -v : v; end endfunction

    // check one frame's change against the model (frame() already ran)
    task check_step;
        input integer allow_cap_or_edge;
        integer dvx, dvy, ex, ey;
        begin
            ex = exp_gx(0); ey = exp_gy(0);
            dvx = vel_x - prev_vx; dvy = vel_y - prev_vy;
            if (!allow_cap_or_edge) begin
                if (iabs(dvx - ex) > 1) begin errors = errors + 1; $display("FAIL: dvx %0d, model %0d (sin_q %0d)", dvx, ex, sin_q); end
                if (iabs(dvy - ey) > 1) begin errors = errors + 1; $display("FAIL: dvy %0d, model %0d (cos_q %0d)", dvy, ey, cos_q); end
                if (ball_x - prev_px !== vel_x) begin errors = errors + 1; $display("FAIL: x moved %0d, velocity %0d", ball_x - prev_px, vel_x); end
                if (ball_y - prev_py !== vel_y) begin errors = errors + 1; $display("FAIL: y moved %0d, velocity %0d", ball_y - prev_py, vel_y); end
            end
            if (iabs(vel_x) > CAP || iabs(vel_y) > CAP) begin errors = errors + 1; $display("FAIL: velocity (%0d,%0d) beyond the cap %0d", vel_x, vel_y, CAP); end
            if (iabs(ball_x) > LIMIT || iabs(ball_y) > LIMIT) begin errors = errors + 1; $display("FAIL: ball (%0d,%0d) beyond the map edge %0d", ball_x, ball_y, LIMIT); end
        end
    endtask

    integer i, a, mag_err, max_mag_err, gx_obs, gy_obs;
    real mag;
    initial begin
        done_count = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // 1) placement on the start tile: tile (11,11) -> 16 px right and down of the map centre
        do_init(5'd11, 5'd11);
        if (ball_x !== 18'sd4096 || ball_y !== 18'sd4096 || vel_x !== 0 || vel_y !== 0) begin
            errors = errors + 1; $display("FAIL: start (%0d,%0d) vel (%0d,%0d), expected (4096,4096) at rest", ball_x, ball_y, vel_x, vel_y);
        end
        do_init(5'd1, 5'd19);               // N = 10 start/goal corners
        if (ball_x !== -(9 * 4096) || ball_y !== (9 * 4096)) begin
            errors = errors + 1; $display("FAIL: tile (1,19) -> (%0d,%0d), expected (%0d,%0d)", ball_x, ball_y, -(9 * 4096), 9 * 4096);
        end

        // 2) angle 0: gravity is screen-down = +y in the maze frame
        do_init(5'd10, 5'd10);              // map centre
        set_angle(0);
        for (i = 0; i < 6; i = i + 1) begin
            frame; check_step(0);
            if (vel_y !== 64 * (i + 1) || vel_x !== 0) begin errors = errors + 1; $display("FAIL: angle 0 frame %0d: vel (%0d,%0d)", i, vel_x, vel_y); end
        end
        if (!(ball_y > 0 && ball_x == 0)) begin errors = errors + 1; $display("FAIL: ball did not fall straight down"); end

        // 3) direction of gravity for each quarter turn
        for (a = 0; a < 4096; a = a + 1024) begin
            do_init(5'd10, 5'd10); set_angle(a);
            frame; check_step(0);
            gx_obs = vel_x; gy_obs = vel_y;
            case (a)
                0:    if (!(gx_obs == 0   && gy_obs == 64))  begin errors = errors + 1; $display("FAIL: angle   0 -> g (%0d,%0d)", gx_obs, gy_obs); end
                1024: if (!(gx_obs == 64  && gy_obs == 0))   begin errors = errors + 1; $display("FAIL: angle  90 -> g (%0d,%0d)", gx_obs, gy_obs); end
                2048: if (!(gx_obs == 0   && gy_obs == -64)) begin errors = errors + 1; $display("FAIL: angle 180 -> g (%0d,%0d)", gx_obs, gy_obs); end
                3072: if (!(gx_obs == -64 && gy_obs == 0))   begin errors = errors + 1; $display("FAIL: angle 270 -> g (%0d,%0d)", gx_obs, gy_obs); end
            endcase
        end

        // 4) constant magnitude and model agreement at many angles
        max_mag_err = 0;
        for (a = 0; a < 4096; a = a + 97) begin
            do_init(5'd10, 5'd10); set_angle(a);
            frame; check_step(0);
            mag = $sqrt(1.0 * vel_x * vel_x + 1.0 * vel_y * vel_y);
            mag_err = $rtoi(mag + 0.5) - 64; if (mag_err < 0) mag_err = -mag_err;
            if (mag_err > max_mag_err) max_mag_err = mag_err;
        end
        if (max_mag_err > 1) begin errors = errors + 1; $display("FAIL: gravity magnitude off by %0d", max_mag_err); end

        // 5) the velocity cap: fall for a long time at angle 0 from the top of the map
        do_init(5'd10, 5'd0); set_angle(0);
        begin : capblock
            integer seen_cap;
            seen_cap = 0;
            for (i = 0; i < 40; i = i + 1) begin
                frame; check_step(1);
                if (vel_y == CAP) seen_cap = 1;
            end
            if (!seen_cap) begin errors = errors + 1; $display("FAIL: velocity never reached the cap in 40 frames"); end
        end

        // 6) map edge: the ball stops there (no walls yet), velocity of that axis is 0
        for (i = 0; i < 80; i = i + 1) begin frame; check_step(1); end
        if (ball_y !== LIMIT || vel_y !== 0) begin errors = errors + 1; $display("FAIL: ball rests at y=%0d vel %0d, expected %0d and 0", ball_y, vel_y, LIMIT); end

        // 7) rotating while moving: gravity follows the new angle at once
        do_init(5'd10, 5'd10); set_angle(0);
        for (i = 0; i < 5; i = i + 1) frame;
        set_angle(2048);                      // upside down
        frame; check_step(0);
        if (!(vel_y == 5 * 64 - 64)) begin errors = errors + 1; $display("FAIL: after the turn vel_y %0d, expected %0d", vel_y, 5 * 64 - 64); end

        // 8) phys_en = 0 holds the ball; a frame without PLAY changes nothing
        do_init(5'd10, 5'd10); set_angle(0);
        phys_en = 1'b0;
        done_count = 0;
        for (i = 0; i < 5; i = i + 1) frame_idle;
        if (done_count != 0) begin errors = errors + 1; $display("FAIL: phys_done pulsed while phys_en = 0"); end
        if (vel_x !== 0 || vel_y !== 0 || ball_x !== 0 || ball_y !== 0) begin errors = errors + 1; $display("FAIL: ball moved while phys_en = 0"); end
        phys_en = 1'b1;

        // 9) one phys_done per frame; none in between
        done_count = 0;
        for (i = 0; i < 10; i = i + 1) frame;
        // (frame() with phys_en=1 on a ball at rest produces one done each)
        if (done_count != 10) begin errors = errors + 1; $display("FAIL: %0d phys_done pulses for 10 frames", done_count); end

        if (errors == 0) $display("PASS: ball_physics - gravity direction and size, cap, map-edge stop, rotation, placement");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
