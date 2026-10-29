`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for ball_physics (Stories 3.1 and 3.2).
// Gravity is checked against a real-number model, g*(sin, cos) with g = 0.15
// px/frame^2; carried fractional bits preserve the average. Free flight must
// follow the new velocity exactly. Walls come from a real maze_ram loaded through its write port; the
// bench keeps its own copy of the map to check that the ball's box (centre
// +/- 5 px, right/bottom edge exclusive) never overlaps a wall tile.
module tb_ball_physics;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg phys_init = 1'b0;
    reg phys_en = 1'b1;
    reg [4:0] spawn_col = 5'd11, spawn_row = 5'd11;
    reg [4:0] goal_col = 5'd1, goal_row = 5'd1;
    reg signed [15:0] sin_q = 16'sd0, cos_q = 16'sd16384;
    reg [1:0] restit = 2'd0;
    wire signed [17:0] ball_x, ball_y;
    wire signed [11:0] vel_x, vel_y;
    wire phys_done;
    wire in_goal;
    wire [8:0] raddr_p;
    wire rdata_p;

    reg       map_we = 1'b0;
    reg [8:0] map_waddr = 9'd0;
    reg       map_wdata = 1'b0;

    always #5 clk = ~clk;

    maze_ram ram_i (
        .clk(clk), .we(map_we), .waddr(map_waddr), .wdata(map_wdata),
        .raddr_p(raddr_p), .rdata_p(rdata_p),
        .ren_r(1'b0), .raddr_r(9'd0), .rdata_r()
    );

    ball_physics dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .phys_init(phys_init), .phys_en(phys_en),
        .spawn_col(spawn_col), .spawn_row(spawn_row),
        .goal_col(goal_col), .goal_row(goal_row), .sin_q(sin_q), .cos_q(cos_q),
        .restitution_sel(restit), .maze_raddr(raddr_p), .maze_rdata(rdata_p),
        .ball_x(ball_x), .ball_y(ball_y), .vel_x(vel_x), .vel_y(vel_y),
        .phys_done(phys_done), .in_goal(in_goal)
    );

    localparam real PI = 3.14159265358979323846;
    localparam integer CAP = 1280;
    localparam integer OFF = 168 * 256;          // map centre, absolute maze pixels in Q9.8
    localparam integer R   = 5 * 256;
    localparam integer FLOOR_EDGE = 147 * 256;   // centre resting against the border wall of the open room
    integer errors = 0;
    integer done_count;
    always @(posedge clk) if (phys_done) done_count <= done_count + 1;

    // ---- the map: bench copy plus maze_ram ----
    reg map_t [0:440];
    integer mi;

    task map_open_room;                           // border walls, floor inside
        integer r, c;
        begin
            for (r = 0; r < 21; r = r + 1)
                for (c = 0; c < 21; c = c + 1)
                    map_t[r * 21 + c] = (r == 0 || r == 20 || c == 0 || c == 20);
        end
    endtask

    task map_load;                                // copy map_t into maze_ram
        begin
            for (mi = 0; mi < 441; mi = mi + 1) begin
                @(negedge clk); map_we = 1'b1; map_waddr = mi; map_wdata = map_t[mi];
            end
            @(negedge clk); map_we = 1'b0;
        end
    endtask

    // 1 if the box around (x, y) overlaps a wall tile or leaves the map
    function box_hits_wall;
        input integer x, y;
        integer ax, ay, c0, c1, r0, r1, r, c;
        begin
            ax = x + OFF; ay = y + OFF;
            box_hits_wall = 1'b0;
            if (ax - R < 0 || ay - R < 0) box_hits_wall = 1'b1;
            else begin
                c0 = (ax - R) / 4096; c1 = (ax + R - 1) / 4096;
                r0 = (ay - R) / 4096; r1 = (ay + R - 1) / 4096;
                if (c1 > 20 || r1 > 20) box_hits_wall = 1'b1;
                else
                    for (r = r0; r <= r1; r = r + 1)
                        for (c = c0; c <= c1; c = c + 1)
                            if (map_t[r * 21 + c]) box_hits_wall = 1'b1;
            end
        end
    endfunction

    // expected bounce: -restitution(|v|) * sign(v), shift-and-add on the magnitude
    function integer bounce;
        input integer v;
        input integer sel;
        integer m, b;
        begin
            m = (v < 0) ? -v : v;
            case (sel)
                0: b = m >> 1;
                1: b = (m >> 1) + (m >> 2);
                2: b = (m >> 1) + (m >> 3);
                default: b = (m >> 2) + (m >> 3);
            endcase
            bounce = (v < 0) ? b : -b;
        end
    endfunction

    task set_angle;                      // angle in 4096 steps = 360 degrees
        input integer a;
        real th;
        begin
            th = 2.0 * PI * a / 4096.0;
            sin_q = $rtoi($floor(16384.0 * $sin(th) + 0.5));
            cos_q = $rtoi($floor(16384.0 * $cos(th) + 0.5));
        end
    endtask

    task no_gravity;                     // sin = cos = 0: the ball coasts
        begin sin_q = 16'sd0; cos_q = 16'sd0; end
    endtask

    // One frame: pulse frame_tick, wait for the update to finish.
    integer prev_vx, prev_vy, prev_px, prev_py, wait_n;
    task frame;
        begin
            prev_vx = vel_x; prev_vy = vel_y; prev_px = ball_x; prev_py = ball_y;
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            wait_n = 0;
            while (!phys_done && wait_n < 100) begin @(posedge clk); wait_n = wait_n + 1; end
            @(negedge clk);
            if (wait_n >= 100) begin errors = errors + 1; $display("FAIL: phys_done never came"); end
            repeat (4) @(posedge clk);
        end
    endtask

    // A frame while the game is not in PLAY: no update, no phys_done.
    task frame_idle;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (60) @(posedge clk);
        end
    endtask

    task do_init;
        input [4:0] c, r;
        begin
            spawn_col = c; spawn_row = r;
            @(negedge clk); phys_init = 1'b1;
            @(negedge clk); phys_init = 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    // Expected per-frame gravity increment; fractional carry may place an
    // individual increment one LSB either side of this rounded model.
    function integer exp_gx; input integer dummy; begin exp_gx = $rtoi($floor(38.4 * sin_q / 16384.0 + 0.5)); end endfunction
    function integer exp_gy; input integer dummy; begin exp_gy = $rtoi($floor(38.4 * cos_q / 16384.0 + 0.5)); end endfunction
    function integer iabs; input integer v; begin iabs = (v < 0) ? -v : v; end endfunction

    // Checks after every frame: cap, box clear of walls, step <= 5 px per axis
    // (a 16 px wall can then never be crossed). With free = 1, the step must
    // also match the gravity model exactly (only where no wall is in reach).
    task check_step;
        input integer free;
        integer dvx, dvy, ex, ey;
        begin
            ex = exp_gx(0); ey = exp_gy(0);
            dvx = vel_x - prev_vx; dvy = vel_y - prev_vy;
            if (free) begin
                if (iabs(dvx - ex) > 1) begin errors = errors + 1; $display("FAIL: dvx %0d, model %0d (sin_q %0d)", dvx, ex, sin_q); end
                if (iabs(dvy - ey) > 1) begin errors = errors + 1; $display("FAIL: dvy %0d, model %0d (cos_q %0d)", dvy, ey, cos_q); end
                if (ball_x - prev_px !== vel_x) begin errors = errors + 1; $display("FAIL: x moved %0d, velocity %0d", ball_x - prev_px, vel_x); end
                if (ball_y - prev_py !== vel_y) begin errors = errors + 1; $display("FAIL: y moved %0d, velocity %0d", ball_y - prev_py, vel_y); end
            end
            if (iabs(vel_x) > CAP || iabs(vel_y) > CAP) begin errors = errors + 1; $display("FAIL: velocity (%0d,%0d) beyond the cap %0d", vel_x, vel_y, CAP); end
            if (iabs(ball_x - prev_px) > CAP || iabs(ball_y - prev_py) > CAP) begin
                errors = errors + 1; $display("FAIL: step (%0d,%0d) longer than 5 px", ball_x - prev_px, ball_y - prev_py);
            end
            if (box_hits_wall(ball_x, ball_y)) begin
                errors = errors + 1; $display("FAIL: ball box at (%0d,%0d) overlaps a wall", ball_x, ball_y);
            end
        end
    endtask

    // Fire the ball from the room centre at one wall and check the hit exactly.
    // dir: 0 = +x (right), 1 = -x (left), 2 = +y (floor), 3 = -y (ceiling).
    // Accelerate with gravity g (Q4.8 per frame) for k frames, then coast with
    // no gravity: the speed must not change until the wall, and the hit must
    // clamp the box to the wall, give bounce() exactly, stay within 2 LSB of
    // the nominal ratio, and leave the other axis at rest.
    real ratio;
    integer wh_v, wh_after, wh_pos, wh_opos, wh_ovel, wh_hit, wh_i, d;
    task wall_hit;
        input integer dir, sel, g, k;
        begin
            restit = sel;
            ratio = (sel == 0) ? 0.5 : (sel == 1) ? 0.75 : (sel == 2) ? 0.625 : 0.375;
            do_init(5'd10, 5'd10);
            sin_q = (dir == 0) ? g * 256 : (dir == 1) ? -g * 256 : 0;
            cos_q = (dir == 2) ? g * 256 : (dir == 3) ? -g * 256 : 0;
            for (wh_i = 0; wh_i < k; wh_i = wh_i + 1) frame;
            no_gravity;
            wh_v = (dir < 2) ? vel_x : vel_y;
            wh_hit = 0;
            for (wh_i = 0; wh_i < 400 && !wh_hit; wh_i = wh_i + 1) begin
                frame; check_step(0);
                wh_after = (dir < 2) ? vel_x : vel_y;
                wh_pos   = (dir < 2) ? ball_x : ball_y;
                wh_opos  = (dir < 2) ? ball_y : ball_x;
                wh_ovel  = (dir < 2) ? vel_y : vel_x;
                if (wh_after == wh_v) begin
                    if (((dir < 2) ? ball_x - prev_px : ball_y - prev_py) !== wh_v) begin
                        errors = errors + 1; $display("FAIL: wall %0d coasting step differs from velocity %0d", dir, wh_v);
                    end
                end else begin
                    wh_hit = 1;
                    if (wh_after !== bounce(wh_v, sel) || wh_pos !== ((dir == 0 || dir == 2) ? FLOOR_EDGE : -FLOOR_EDGE) ||
                        wh_opos !== 0 || wh_ovel !== 0) begin
                        errors = errors + 1;
                        $display("FAIL: wall %0d restitution %0d speed %0d: after the hit pos=%0d v=%0d (other axis %0d, %0d), expected pos=%0d v=%0d",
                                 dir, sel, wh_v, wh_pos, wh_after, wh_opos, wh_ovel,
                                 (dir == 0 || dir == 2) ? FLOOR_EDGE : -FLOOR_EDGE, bounce(wh_v, sel));
                    end
                    if (iabs(wh_after) - ratio * iabs(wh_v) >= 2.0 || ratio * iabs(wh_v) - iabs(wh_after) >= 2.0) begin
                        errors = errors + 1; $display("FAIL: wall %0d restitution %0d: |%0d| -> |%0d| is not %f of it", dir, sel, wh_v, wh_after, ratio);
                    end
                end
            end
            if (!wh_hit) begin errors = errors + 1; $display("FAIL: wall %0d restitution %0d speed %0d: velocity changed without a wall (drag?)", dir, sel, wh_v); end
        end
    endtask

    integer i, a, k, s, mag_err, max_mag_err, gx_obs, gy_obs, hit_v, hit_frame, bounces, m, step, seed;
    integer rest_x, rest_y, vx_hold, still;
    real mag;
    initial begin
        done_count = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        map_open_room; map_load;
        repeat (4) @(posedge clk);

        // ================= Story 3.1 checks, in the open room =================
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
            frame; check_step(1);
            if (iabs(vel_y - $rtoi($floor(38.4 * (i + 1) + 0.5))) > 1 || vel_x !== 0) begin
                errors = errors + 1; $display("FAIL: angle 0 frame %0d: vel (%0d,%0d)", i, vel_x, vel_y);
            end
        end
        if (!(ball_y > 0 && ball_x == 0)) begin errors = errors + 1; $display("FAIL: ball did not fall straight down"); end

        // 3) direction of gravity for each quarter turn
        for (a = 0; a < 4096; a = a + 1024) begin
            do_init(5'd10, 5'd10); set_angle(a);
            frame; check_step(1);
            gx_obs = vel_x; gy_obs = vel_y;
            case (a)
                0:    if (iabs(gx_obs) > 1 || iabs(gy_obs - 38) > 1) begin errors = errors + 1; $display("FAIL: angle   0 -> g (%0d,%0d)", gx_obs, gy_obs); end
                1024: if (iabs(gx_obs - 38) > 1 || iabs(gy_obs) > 1) begin errors = errors + 1; $display("FAIL: angle  90 -> g (%0d,%0d)", gx_obs, gy_obs); end
                2048: if (iabs(gx_obs) > 1 || iabs(gy_obs + 38) > 1) begin errors = errors + 1; $display("FAIL: angle 180 -> g (%0d,%0d)", gx_obs, gy_obs); end
                3072: if (iabs(gx_obs + 38) > 1 || iabs(gy_obs) > 1) begin errors = errors + 1; $display("FAIL: angle 270 -> g (%0d,%0d)", gx_obs, gy_obs); end
            endcase
        end

        // 4) constant magnitude and model agreement at many angles
        max_mag_err = 0;
        for (a = 0; a < 4096; a = a + 97) begin
            do_init(5'd10, 5'd10); set_angle(a);
            frame; check_step(1);
            mag = $sqrt(1.0 * vel_x * vel_x + 1.0 * vel_y * vel_y);
            mag_err = $rtoi(mag + 0.5) - 38; if (mag_err < 0) mag_err = -mag_err;
            if (mag_err > max_mag_err) max_mag_err = mag_err;
        end
        if (max_mag_err > 1) begin errors = errors + 1; $display("FAIL: gravity magnitude off by %0d", max_mag_err); end

        // 5) the velocity cap: fall for a long time at angle 0 from the top row of the room
        do_init(5'd10, 5'd1); set_angle(0);
        begin : capblock
            integer seen_cap;
            seen_cap = 0;
            for (i = 0; i < 40; i = i + 1) begin
                frame; check_step(0);
                if (vel_y == CAP) seen_cap = 1;
            end
            if (!seen_cap) begin errors = errors + 1; $display("FAIL: velocity never reached the cap in 40 frames"); end
        end

        // 6) it lands on the floor, bounces down to rest, and then stays put (no jitter)
        for (i = 0; i < 150; i = i + 1) begin frame; check_step(0); end
        rest_y = ball_y;
        for (i = 0; i < 30; i = i + 1) begin
            frame; check_step(0);
            if (ball_y !== rest_y || ball_x !== 0) begin errors = errors + 1; $display("FAIL: resting ball moved to (%0d,%0d)", ball_x, ball_y); end
        end
        if (rest_y !== FLOOR_EDGE || iabs(vel_y) >= 40) begin
            errors = errors + 1; $display("FAIL: ball rests at y=%0d vel %0d, expected %0d and |vel| < 40", rest_y, vel_y, FLOOR_EDGE);
        end

        // 7) rotating while moving: gravity follows the new angle at once
        do_init(5'd10, 5'd10); set_angle(0);
        for (i = 0; i < 5; i = i + 1) frame;
        set_angle(2048);                      // upside down
        frame; check_step(1);
        if (iabs(vel_y - 154) > 1) begin errors = errors + 1; $display("FAIL: after the turn vel_y %0d, expected about 154", vel_y); end

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
        if (done_count != 10) begin errors = errors + 1; $display("FAIL: %0d phys_done pulses for 10 frames", done_count); end

        // ================= Story 3.2: collisions =================
        // 10) bounce ratio for every restitution, against all four walls, at even
        //     (g = 64) and uneven (g = 45) speeds; no drag while coasting.
        for (d = 0; d < 4; d = d + 1)
            for (s = 0; s < 4; s = s + 1) begin
                wall_hit(d, s, 64, 4);  wall_hit(d, s, 64, 28);
                wall_hit(d, s, 45, 5);  wall_hit(d, s, 45, 23);
            end

        // 11) tangential velocity is untouched by a bounce: y reaches the floor first
        restit = 2'd0;
        do_init(5'd10, 5'd10); set_angle(400);      // about 35 degrees: gx < gy
        for (i = 0; i < 10; i = i + 1) frame;
        no_gravity;
        vx_hold = vel_x; hit_v = vel_y; hit_frame = 0;
        for (i = 0; i < 400 && !hit_frame; i = i + 1) begin
            frame; check_step(0);
            if (vel_y != hit_v) begin
                hit_frame = 1;
                if (vel_y !== bounce(hit_v, 0) || vel_x !== vx_hold || ball_x - prev_px !== vx_hold) begin
                    errors = errors + 1; $display("FAIL: floor bounce changed the tangential motion: vx %0d -> %0d, dx %0d", vx_hold, vel_x, ball_x - prev_px);
                end
            end
        end
        if (!hit_frame) begin errors = errors + 1; $display("FAIL: tangential test never hit the floor"); end

        // 12) a bounce too small to survive stops the axis: weak gravity (+1 per frame) into the right wall
        restit = 2'd0;
        do_init(5'd19, 5'd10); sin_q = 16'sd256; cos_q = 16'sd0;   // gx = 1, gy = 0
        for (i = 0; i < 300; i = i + 1) begin frame; check_step(0); end
        if (ball_x !== FLOOR_EDGE || vel_x !== 0) begin
            errors = errors + 1; $display("FAIL: weak push should end at rest on the wall: x=%0d vx=%0d", ball_x, vel_x);
        end

        // 13) diagonal corner tile: only tile (11,11) is a wall next to the start (10,10).
        //     x must pass freely while y is stopped by the diagonal tile.
        map_open_room; map_t[11 * 21 + 11] = 1'b1; map_load;
        restit = 2'd0;
        do_init(5'd10, 5'd10); set_angle(512);      // 45 degrees, down-right
        hit_frame = 0;
        for (i = 0; i < 60; i = i + 1) begin
            frame; check_step(0);
            if (!hit_frame && prev_vy > 0 && vel_y <= 0 && ball_x - prev_px == vel_x && vel_x > 0) hit_frame = 1;
        end
        if (!hit_frame) begin errors = errors + 1; $display("FAIL: the diagonal tile never stopped y while x moved freely"); end

        // 14) settling in a corner under diagonal gravity (bounciest setting): it stops and stays
        map_open_room; map_load;
        restit = 2'd1;
        do_init(5'd10, 5'd10); set_angle(512);
        for (i = 0; i < 700; i = i + 1) begin frame; check_step(0); end
        rest_x = ball_x; rest_y = ball_y;
        for (i = 0; i < 50; i = i + 1) begin
            frame; check_step(0);
            if (ball_x !== rest_x || ball_y !== rest_y) begin errors = errors + 1; $display("FAIL: ball jitters in the corner (%0d,%0d)", ball_x, ball_y); end
        end
        if (rest_x !== FLOOR_EDGE || rest_y !== FLOOR_EDGE) begin
            errors = errors + 1; $display("FAIL: corner rest at (%0d,%0d), expected (%0d,%0d)", rest_x, rest_y, FLOOR_EDGE, FLOOR_EDGE);
        end
        // ... and in the opposite (top-left) corner, against the left wall and the ceiling
        do_init(5'd10, 5'd10); set_angle(2560);     // 225 degrees, up-left
        for (i = 0; i < 700; i = i + 1) begin frame; check_step(0); end
        rest_x = ball_x; rest_y = ball_y;
        for (i = 0; i < 50; i = i + 1) begin
            frame; check_step(0);
            if (ball_x !== rest_x || ball_y !== rest_y) begin errors = errors + 1; $display("FAIL: ball jitters in the top-left corner (%0d,%0d)", ball_x, ball_y); end
        end
        if (rest_x !== -FLOOR_EDGE || rest_y !== -FLOOR_EDGE) begin
            errors = errors + 1; $display("FAIL: top-left corner rest at (%0d,%0d), expected (%0d,%0d)", rest_x, rest_y, -FLOOR_EDGE, -FLOOR_EDGE);
        end

        // 15) no tunnelling: random maps, every restitution, the maze turning
        //     continuously so the ball is fired at walls from all angles at up to the cap.
        seed = 32'h3A11CE;
        bounces = 0;
        for (m = 0; m < 24; m = m + 1) begin
            map_open_room;
            for (mi = 0; mi < 441; mi = mi + 1)
                if (!map_t[mi] && ($random(seed) & 32'h7) < 3) map_t[mi] = 1'b1;   // about 37% walls
            begin : pick_start
                integer sc, sr;
                sc = 1 + ((($random(seed) & 32'h7FFF) % 19));
                sr = 1 + ((($random(seed) & 32'h7FFF) % 19));
                map_t[sr * 21 + sc] = 1'b0;
                map_load;
                restit = m % 4;
                do_init(sc, sr);
            end
            step = 23 + 31 * (m % 7);
            a = ($random(seed) & 32'hFFF);
            for (i = 0; i < 220; i = i + 1) begin
                if ((i % 40) == 39) a = ($random(seed) & 32'hFFF);     // sometimes jump to a new angle
                else a = (a + step) & 32'hFFF;
                set_angle(a);
                frame; check_step(0);
                if (((prev_vx > 0) && (vel_x < 0)) || ((prev_vx < 0) && (vel_x > 0)) ||
                    ((prev_vy > 0) && (vel_y < 0)) || ((prev_vy < 0) && (vel_y > 0)))
                    bounces = bounces + 1;
            end
        end
        $display("sweep: 24 maps, %0d frames, %0d direction reversals", 24 * 220, bounces);
        if (bounces < 200) begin errors = errors + 1; $display("FAIL: the sweep hardly hit any walls (%0d reversals)", bounces); end

        if (errors == 0) $display("PASS: ball_physics - gravity, cap, rotation, placement; bounces on all four walls at every restitution, no drag, tangential kept, corner settle, no tunnelling");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
