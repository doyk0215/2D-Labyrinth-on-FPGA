`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 3.3 goal detection uses the ball centre, not its radius.
module tb_goal_detection;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [4:0] goal_col = 5'd1;
    reg [4:0] goal_row = 5'd1;
    reg [3:0] n_cells = 4'd10;
    wire signed [17:0] ball_x, ball_y;
    wire in_goal;
    integer errors = 0;
    integer n, tile, left_q, top_q, right_q, bottom_q;

    always #5 clk = ~clk;

    ball_physics dut (
        .clk(clk), .rst(rst), .frame_tick(1'b0), .phys_init(1'b0), .phys_en(1'b0),
        .spawn_col(5'd19), .spawn_row(5'd19), .goal_col(goal_col), .goal_row(goal_row), .n_cells(n_cells),
        .sin_q(16'sd0), .cos_q(16'sd16384), .restitution_sel(2'd0),
        .maze_raddr(), .maze_rdata(1'b0), .ball_x(ball_x), .ball_y(ball_y),
        .vel_x(), .vel_y(), .phys_done(), .in_goal(in_goal)
    );

    task expect_goal;
        input integer x;
        input integer y;
        input expected;
        input [255:0] description;
        begin
            force dut.ball_x = x;
            force dut.ball_y = y;
            #1;
            if (in_goal !== expected) begin
                $display("FAIL: %0s N=%0d goal (%0d,%0d), ball (%0d,%0d), bounds x[%0d,%0d) y[%0d,%0d), OFF=%0d, in_goal=%b",
                         description, n_cells, goal_col, goal_row, x, y,
                         dut.goal_x_min, dut.goal_x_max, dut.goal_y_min, dut.goal_y_max, dut.OFF, in_goal);
                errors = errors + 1;
            end
            release dut.ball_x;
            release dut.ball_y;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        // Stage-sized maps place the green goal at tile (1,1) for N=2..15.
        for (n = 2; n <= 15; n = n + 1) begin
            n_cells = n;
            tile = 1;
            goal_col = tile;
            goal_row = tile;
            left_q = tile * 4096 - (n * 4096 + 2048);
            top_q = tile * 4096 - (n * 4096 + 2048);
            right_q = left_q + 4096;
            bottom_q = top_q + 4096;
            expect_goal(left_q + 2048, top_q + 2048, 1'b1, "tile centre");
            expect_goal(left_q, top_q, 1'b1, "inclusive top-left edge");
            expect_goal(right_q - 1, bottom_q - 1, 1'b1, "last Q9.8 unit in tile");
            // The centre is one fractional unit outside, while the 5 px ball
            // radius overlaps the goal tile. It must not count as a win.
            expect_goal(left_q - 1, top_q + 2048, 1'b0, "radius-only left overlap");
            expect_goal(right_q, top_q + 2048, 1'b0, "exclusive right edge");
            expect_goal(left_q + 2048, top_q - 1, 1'b0, "exclusive top edge");
            expect_goal(left_q + 2048, bottom_q, 1'b0, "exclusive bottom edge");
        end

        if (errors == 0)
            $display("PASS: goal detection uses the ball centre and half-open tile bounds for N=2..15");
        else
            $display("FAIL: goal detection had %0d errors", errors);
        $finish;
    end
endmodule
