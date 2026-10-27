`timescale 1ns / 1ps

// End-to-end check of the ball on the real top (Stories 3.1, 3.2): the ball
// colour is searched for in the VGA pixel stream of whole frames. Checks that
// the disc is complete and round, that it sits where ball_physics says (so
// ball_overlay and render are aligned), that at angle 0 it falls or rests
// without drifting sideways, that its box never overlaps a wall of the
// generated maze, and that it follows a rotation. Needs the full design
// (MouseCtl is a VHDL module; Icarus runs this with a stand-in whose buttons
// stay 0). The power-on reset starts the game; BTNC stays released.
module tb_top_ball;
    reg clk = 1'b0;
    reg btnC = 1'b0;
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
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnL(btnL), .btnR(1'b0), .btnD(1'b0),
        .sw(16'h0001), .led(led), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    localparam real PI = 3.14159265358979323846;
    integer errors = 0;

    // ---- pixel statistics for the frame in progress ----
    reg [9:0] px_d, py_d;
    integer n_clk, sum_x, sum_y, min_x, max_x, min_y, max_y;
    wire is_ball = (vga_r == 4'hf) && (vga_g == 4'hc) && (vga_b == 4'h0);
    always @(posedge clk) begin
        px_d <= dut.pixel_x; py_d <= dut.pixel_y;      // vga_* lag pixel_x/y by one clock
        if (is_ball) begin
            n_clk = n_clk + 1; sum_x = sum_x + px_d; sum_y = sum_y + py_d;
            if (px_d < min_x) min_x = px_d; if (px_d > max_x) max_x = px_d;
            if (py_d < min_y) min_y = py_d; if (py_d > max_y) max_y = py_d;
        end
    end

    integer frames_since_init = 0;
    always @(posedge clk) begin
        if (dut.phys_init) frames_since_init <= 0;       // game_ctrl places the ball when PLAY begins
        else if (dut.phys_done) frames_since_init <= frames_since_init + 1;
    end

    // wait for the start of vertical blanking N times
    task wait_frames;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin @(posedge dut.frame_tick); @(posedge clk); end
        end
    endtask

    // Measure one whole frame, starting at a frame_tick.
    real cx, cy, ex, ey, th;
    integer k_at_frame;
    task measure;
        input integer label;
        begin
            @(posedge dut.frame_tick);
            repeat (40) @(posedge clk);                 // ball position settles in blanking
            k_at_frame = frames_since_init;
            n_clk = 0; sum_x = 0; sum_y = 0; min_x = 1023; max_x = 0; min_y = 1023; max_y = 0;
            @(posedge dut.frame_tick);                  // one whole frame of pixels
            if (n_clk != 81 * 4) begin errors = errors + 1; $display("FAIL[%0d]: ball covers %0d pixel-clocks, expected %0d (81 pixels)", label, n_clk, 81 * 4); end
            cx = 1.0 * sum_x / n_clk; cy = 1.0 * sum_y / n_clk;
            if (max_x - min_x != 10 || max_y - min_y != 10) begin errors = errors + 1; $display("FAIL[%0d]: ball box %0dx%0d, expected 11x11", label, max_x - min_x + 1, max_y - min_y + 1); end
            // where ball_physics says the ball is, seen through the current angle
            th = 2.0 * PI * dut.angle / 4096.0;
            ex = 320.0 + (dut.ball_x / 256.0) * $cos(th) - (dut.ball_y / 256.0) * $sin(th);
            ey = 240.0 + (dut.ball_x / 256.0) * $sin(th) + (dut.ball_y / 256.0) * $cos(th);
            $display("frame %0d: k=%0d angle=%0d ball at pixels (%f,%f), physics says (%f,%f)", label, k_at_frame, dut.angle, cx, cy, ex, ey);
            if ((cx - ex) > 1.0 || (ex - cx) > 1.0 || (cy - ey) > 1.0 || (ey - cy) > 1.0) begin
                errors = errors + 1; $display("FAIL[%0d]: drawn centre (%f,%f) differs from the physics position (%f,%f)", label, cx, cy, ex, ey);
            end
            if (box_in_wall(dut.ball_x, dut.ball_y)) begin
                errors = errors + 1; $display("FAIL[%0d]: ball box at (%0d,%0d) overlaps a wall of the maze", label, dut.ball_x, dut.ball_y);
            end
        end
    endtask

    // 1 if the ball's box (centre +/- 5 px, right/bottom edge exclusive, Q9.8
    // from the map centre) overlaps a wall tile of the real maze_ram
    function box_in_wall;
        input integer x, y;
        integer ax, ay, r, c;
        begin
            ax = x + 168 * 256; ay = y + 168 * 256;
            box_in_wall = 1'b0;
            for (r = (ay - 1280) / 4096; r <= (ay + 1279) / 4096; r = r + 1)
                for (c = (ax - 1280) / 4096; c <= (ax + 1279) / 4096; c = c + 1)
                    if (dut.maze_ram_i.tile_mem[r * 21 + c]) box_in_wall = 1'b1;
        end
    endfunction

    real y0, y1, x0, x1, expect_dy, tile_cy;
    integer k0, k1, sc, sr;
    initial begin
        n_clk = 0; sum_x = 0; sum_y = 0; min_x = 1023; max_x = 0; min_y = 1023; max_y = 0;
        wait_frames(3);

        // green start tile (bottom-right) centre on the screen (angle 0): 320 + 16*(col-10), 240 + 16*(row-10).
        // Walls can stop the fall, so the ball is between the tile centre and
        // the model's free-fall depth 0.075*k*(k+1) px below it at g=0.15.
        measure(1);
        x0 = cx; y0 = cy; k0 = k_at_frame;
        sc = dut.start_col; sr = dut.start_row;        // unsigned 5-bit: widen before subtracting
        ex = 320.0 + 16.0 * (sc - 10);
        ey = 240.0 + 16.0 * (sr - 10);
        tile_cy = ey;                                  // measure() reuses ex/ey for the physics position
        if (k0 < 1 || k0 > 6) begin errors = errors + 1; $display("FAIL: unexpected frame count %0d", k0); end
        if (x0 - ex > 1.0 || ex - x0 > 1.0 || y0 < ey - 1.0 || y0 > ey + 0.075 * k0 * (k0 + 1) + 1.0) begin
            errors = errors + 1; $display("FAIL: first frame ball at (%f,%f), expected x %f and y in [%f, %f]", x0, y0, ex, ey, ey + 0.075 * k0 * (k0 + 1));
        end

        // later it is lower or resting on a wall, never higher, and never off sideways
        wait_frames(9);
        measure(2);
        x1 = cx; y1 = cy; k1 = k_at_frame;
        expect_dy = 0.075 * (1.0 * k1 * (k1 + 1) - 1.0 * k0 * (k0 + 1));
        $display("fell %f px between frame counts %0d and %0d, free-fall model %f", y1 - y0, k0, k1, expect_dy);
        if (x1 - x0 > 1.0 || x0 - x1 > 1.0) begin errors = errors + 1; $display("FAIL: ball drifted sideways at angle 0 (%f -> %f)", x0, x1); end
        if (y1 < y0 - 1.0 || y1 - y0 > expect_dy + 1.5) begin errors = errors + 1; $display("FAIL: fall %f px, expected 0 to %f", y1 - y0, expect_dy); end
        // It must really have dropped: at least to the floor of the start cell
        // (3 px below the tile centre; a rebound peaks at most 0.75 px above it).
        if (y1 < tile_cy + 2.0) begin errors = errors + 1; $display("FAIL: ball still at y %f, expected at least %f (did it fall at all?)", y1, tile_cy + 2.0); end

        // rotate: hold btnL for a few frames (counter-clockwise); the ball must follow
        btnL = 1'b1;
        wait_frames(12);
        btnL = 1'b0;
        wait_frames(1);
        measure(3);
        if (dut.angle == 0) begin errors = errors + 1; $display("FAIL: the maze did not rotate"); end

        if (errors == 0) $display("PASS: top ball - complete round disc, aligned with the physics position, falls or rests without crossing walls, follows rotation");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
