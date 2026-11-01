`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 7.2: camera dead zone, smoothing, snap and fixed stages, against a
// software model of the same arithmetic, with a scripted ball path.
module tb_camera;
    reg clk = 0, rst = 1, phys_init = 0, phys_done = 0;
    reg [`N_CELLS_W-1:0] n_cells = 4'd15;
    reg signed [`POS_W-1:0] ball_x = 0, ball_y = 0;
    wire signed [`POS_W-1:0] cam_x, cam_y;
    wire cam_done;
    always #5 clk = ~clk;

    camera dut (
        .clk(clk), .rst(rst), .phys_init(phys_init), .phys_done(phys_done),
        .n_cells(n_cells), .ball_x(ball_x), .ball_y(ball_y),
        .cam_x(cam_x), .cam_y(cam_y), .cam_done(cam_done)
    );

    localparam integer PX = 256;                 // Q9.8
    localparam integer DZ = 48 * PX;
    localparam integer LAG = 40 * PX;            // 5 px/frame << CAM_SHIFT
    localparam integer SCREEN_R = 240 - `BALL_RADIUS;

    integer errors = 0, frames = 0, dones = 0;
    integer m_tx = 0, m_ty = 0, m_cx = 0, m_cy = 0;   // model
    integer last_cx, last_cy;

    always @(posedge clk) if (cam_done) dones = dones + 1;

    // The camera may change only on the clock cam_done rises (ball_overlay
    // captures ball - cam then), or on reset.
    reg signed [`POS_W-1:0] prev_cx = 0, prev_cy = 0;
    reg rst_at_edge;
    always @(posedge clk) begin
        rst_at_edge = rst;                       // what the camera saw on this edge
        #1;
        if (!rst_at_edge && (cam_x != prev_cx || cam_y != prev_cy) && !cam_done) begin
            errors = errors + 1;
            $display("FAIL camera: camera changed without cam_done (cam %0d,%0d)", cam_x, cam_y);
        end
        prev_cx = cam_x; prev_cy = cam_y;
    end

    task check;
        input cond;
        input [511:0] msg;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL camera: %0s (frame %0d, ball %0d,%0d cam %0d,%0d model %0d,%0d)",
                         msg, frames, ball_x, ball_y, cam_x, cam_y, m_cx, m_cy);
            end
        end
    endtask

    // floor division by 2^3, as >>> does on a signed value
    function integer asr3;
        input integer v;
        begin asr3 = (v >= 0) ? v / 8 : -((-v + 7) / 8); end
    endfunction

    function integer follow_target;
        input integer b, t;
        begin
            if (b > t + DZ)      follow_target = b - DZ;
            else if (b < t - DZ) follow_target = b + DZ;
            else                 follow_target = t;
        end
    endfunction

    // One physics frame: present the ball, pulse phys_done, wait for cam_done.
    task frame;
        input integer bx, by;
        integer before;
        begin
            @(negedge clk);
            ball_x = bx; ball_y = by;
            before = dones;
            phys_done = 1; @(negedge clk); phys_done = 0;
            check(!cam_done, "cam_done one clock after phys_done");
            @(negedge clk);
            check(cam_done, "cam_done not two clocks after phys_done");
            repeat (3) @(negedge clk);
            frames = frames + 1;
            check(dones == before + 1, "one cam_done per frame");
            if (n_cells >= 11) begin
                m_tx = follow_target(bx, m_tx);
                m_ty = follow_target(by, m_ty);
                m_cx = m_cx + asr3(m_tx - m_cx);
                m_cy = m_cy + asr3(m_ty - m_cy);
            end else begin
                m_tx = 0; m_ty = 0; m_cx = 0; m_cy = 0;
            end
            check(cam_x == m_cx && cam_y == m_cy, "camera differs from the model");
        end
    endtask

    task init_at;
        input integer bx, by;
        integer before;
        begin
            @(negedge clk);
            before = dones;
            phys_init = 1; @(negedge clk); phys_init = 0;
            ball_x = bx; ball_y = by;            // ball_physics places it one clock later
            check(!cam_done, "cam_done one clock after phys_init");
            @(negedge clk);
            check(cam_done, "cam_done not two clocks after phys_init");
            repeat (3) @(negedge clk);
            check(dones == before + 1, "one cam_done on phys_init");
            if (n_cells >= 11) begin
                m_tx = bx; m_ty = by; m_cx = bx; m_cy = by;
                check(cam_x == bx && cam_y == by, "phys_init did not snap to the ball");
            end else begin
                m_tx = 0; m_ty = 0; m_cx = 0; m_cy = 0;
                check(cam_x == 0 && cam_y == 0, "fixed stage camera left the map centre");
            end
        end
    endtask

    // The offset the screen shows: within the box plus lag, and on screen at any angle.
    task check_on_screen;
        integer dx, dy;
        begin
            dx = ball_x - cam_x; dy = ball_y - cam_y;
            check(dx <= DZ + LAG && dx >= -(DZ + LAG) && dy <= DZ + LAG && dy >= -(DZ + LAG),
                  "ball left the dead zone plus smoothing lag");
            check((1.0 * dx * dx + 1.0 * dy * dy) <= (1.0 * SCREEN_R * PX) * (SCREEN_R * PX),
                  "ball could leave the screen at some angle");
        end
    endtask

    integer i, k, x, y, bounce;
    initial begin
        repeat (4) @(negedge clk); rst = 0;
        check(cam_x == 0 && cam_y == 0, "reset is not the map centre");

        // ---- N = 15: snap at the bottom-right spawn ----
        n_cells = 4'd15;
        init_at(224 * PX, 224 * PX);

        // ---- bounces inside the dead zone do not move the camera ----
        for (k = 0; k < 6; k = k + 1)
            for (i = 0; i < 20; i = i + 1) begin
                bounce = (i < 10) ? i * 47 * PX / 10 : (20 - i) * 47 * PX / 10;
                frame(224 * PX + (k - 3) * 7 * PX, 224 * PX - bounce);
                check(cam_x == 224 * PX && cam_y == 224 * PX, "camera moved inside the dead zone");
            end

        // ---- leave the box at the 5 px/frame cap, up and to the left ----
        x = 224 * PX; y = 224 * PX;
        last_cx = cam_x; last_cy = cam_y;
        for (i = 0; i < 80; i = i + 1) begin
            x = x - 5 * PX; y = y - 5 * PX;
            frame(x, y);
            check(cam_x <= last_cx && cam_y <= last_cy, "camera moved against the ball");
            check(cam_x >= m_tx && cam_y >= m_ty && m_tx >= x - DZ && m_tx <= x + DZ, "camera overshot its target");
            check_on_screen;
            last_cx = cam_x; last_cy = cam_y;
        end
        // ball stops: the camera settles on the box edge without passing it
        for (i = 0; i < 120; i = i + 1) begin
            frame(x, y);
            check(cam_x >= m_tx && cam_y >= m_ty, "camera overshot while settling");
            check_on_screen;
        end
        check(cam_x - (x + DZ) < PX && cam_y - (y + DZ) < PX, "camera did not settle");

        // ---- the other direction, one axis at a time ----
        for (i = 0; i < 90; i = i + 1) begin
            x = x + 5 * PX;
            frame(x, y);
            check_on_screen;
        end
        for (i = 0; i < 90; i = i + 1) begin
            y = y + 5 * PX;
            frame(x, y);
            check_on_screen;
        end

        // ---- phys_done together with phys_init, or one clock after it:
        //      the snap wins and no step uses the old target ----
        for (k = 0; k < 2; k = k + 1) begin
            @(negedge clk);
            i = dones;
            phys_init = 1; phys_done = (k == 0);
            @(negedge clk);
            phys_init = 0; phys_done = (k == 1);
            ball_x = (k ? 150 : -150) * PX; ball_y = (k ? -60 : 60) * PX;
            @(negedge clk); phys_done = 0;
            repeat (4) @(negedge clk);
            m_tx = ball_x; m_ty = ball_y; m_cx = ball_x; m_cy = ball_y;
            check(dones == i + 1, "coincident pulses gave other than one cam_done");
            check(cam_x == ball_x && cam_y == ball_y, "coincident phys_done disturbed the snap");
        end

        // ---- a replay snaps again, without sweeping ----
        init_at(-200 * PX, 210 * PX);
        frame(-200 * PX, 210 * PX);
        check(cam_x == -200 * PX && cam_y == 210 * PX, "camera moved after the snap");

        // ---- N = 5 and N = 10 keep the map centre on every frame ----
        for (k = 0; k < 2; k = k + 1) begin
            n_cells = k ? 4'd10 : 4'd5;
            init_at(64 * PX, 64 * PX);
            for (i = 0; i < 60; i = i + 1) begin
                frame((64 - 3 * i) * PX, (64 - 2 * i) * PX);
                check(cam_x == 0 && cam_y == 0, "fixed stage camera moved");
            end
        end

        // ---- reset returns to the map centre ----
        n_cells = 4'd15;
        init_at(100 * PX, 100 * PX);
        @(negedge clk); rst = 1; @(negedge clk); rst = 0;
        check(cam_x == 0 && cam_y == 0, "reset did not clear the camera");

        if (errors == 0)
            $display("PASS: camera dead zone, smoothing without overshoot, snap and fixed stages (%0d frames)", frames);
        else
            $display("FAIL camera: %0d errors", errors);
        $finish;
    end
endmodule
