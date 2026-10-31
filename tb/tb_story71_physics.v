`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_story71_physics;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg phys_init = 1'b0;
    reg phys_en = 1'b1;
    reg [3:0] n_cells = 4'd15;
    reg [4:0] spawn_col = 5'd29, spawn_row = 5'd15;
    reg [4:0] goal_col = 5'd1, goal_row = 5'd1;
    reg signed [15:0] sin_q = 16'sd16384, cos_q = 16'sd0;
    wire [9:0] maze_raddr;
    wire maze_rdata;
    wire signed [17:0] ball_x, ball_y;
    wire signed [11:0] vel_x, vel_y;
    wire phys_done, in_goal;

    reg map_we = 1'b0;
    reg [9:0] map_waddr = 10'd0;
    reg map_wdata = 1'b1;
    reg map_t [0:960];
    integer i, row, col, guard, errors = 0;

    always #5 clk = ~clk;

    maze_ram ram_i (
        .clk(clk), .we(map_we), .waddr(map_waddr), .wdata(map_wdata),
        .raddr_p(maze_raddr), .rdata_p(maze_rdata),
        .ren_r(1'b0), .raddr_r(10'd0), .rdata_r()
    );

    ball_physics dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .phys_init(phys_init),
        .phys_en(phys_en), .spawn_col(spawn_col), .spawn_row(spawn_row),
        .goal_col(goal_col), .goal_row(goal_row), .n_cells(n_cells),
        .sin_q(sin_q), .cos_q(cos_q), .restitution_sel(2'd0),
        .maze_raddr(maze_raddr), .maze_rdata(maze_rdata),
        .ball_x(ball_x), .ball_y(ball_y), .vel_x(vel_x), .vel_y(vel_y),
        .phys_done(phys_done), .in_goal(in_goal)
    );

    task open_room_n15;
        begin
            for (row = 0; row < 31; row = row + 1)
                for (col = 0; col < 31; col = col + 1)
                    map_t[row * 31 + col] = (row == 0 || row == 30 || col == 0 || col == 30);
        end
    endtask

    task load_map;
        begin
            for (i = 0; i < 961; i = i + 1) begin
                @(negedge clk); map_we = 1'b1; map_waddr = i[9:0]; map_wdata = map_t[i];
            end
            @(negedge clk); map_we = 1'b0;
        end
    endtask

    task init_ball;
        begin
            @(negedge clk); phys_init = 1'b1;
            @(negedge clk); phys_init = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            guard = 0;
            while (!phys_done && guard < 100) begin @(negedge clk); guard = guard + 1; end
            if (!phys_done) begin
                $display("FAIL: N=15 physics frame timed out");
                errors = errors + 1;
            end
        end
    endtask

    integer f, bounced;
    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        open_room_n15();
        load_map();

        // Ball is initialized at the N=15 red start and accelerates into the
        // right outer wall. The 5 px/frame cap must not tunnel through it.
        init_ball();
        bounced = 0;
        for (f = 0; f < 100 && !bounced; f = f + 1) begin
            frame();
            if (vel_x < 0) bounced = 1;
            if (ball_x > (227 * 256) || ball_x < (-248 * 256)) begin
                $display("FAIL: N=15 ball tunneled outside map (x=%0d)", ball_x);
                errors = errors + 1;
                bounced = 1;
            end
        end
        if (!bounced || vel_x >= 0) begin
            $display("FAIL: N=15 right-wall bounce was not observed (x=%0d vx=%0d)", ball_x, vel_x);
            errors = errors + 1;
        end
        if (ball_x !== (227 * 256)) begin
            $display("FAIL: N=15 right-wall clamp x=%0d expected=%0d", ball_x, 227 * 256);
            errors = errors + 1;
        end

        // Goal bounds use the N=15 map centre and the packed goal tile (1,1).
        force dut.ball_x = -14 * 4096;
        force dut.ball_y = -14 * 4096;
        #1;
        if (!in_goal) begin
            $display("FAIL: N=15 goal centre was not detected");
            errors = errors + 1;
        end
        release dut.ball_x;
        release dut.ball_y;

        if (errors == 0) $display("PASS: Story 7.1 N=15 physics bounce, no tunnelling and goal bounds on 31x31 map");
        else             $display("FAIL: Story 7.1 N=15 physics had %0d errors", errors);
        $finish;
    end
endmodule
