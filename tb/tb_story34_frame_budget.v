`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_story34_frame_budget;
    localparam integer VBLANK_BUDGET_CYCLES = 45 * 800 * 4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg gen_start = 1'b0;
    reg [3:0] n_cells = 4'd5;
    reg [31:0] seed = 32'h3A11CE01;
    wire gen_busy, gen_done, maze_we, maze_wdata;
    wire [8:0] maze_waddr;
    wire [4:0] start_col, start_row, goal_col, goal_row;
    reg phys_init = 1'b0;
    reg phys_en = 1'b1;
    reg frame_tick = 1'b0;
    reg signed [15:0] sin_q = 16'sd0;
    reg signed [15:0] cos_q = 16'sd16384;
    reg [1:0] restitution_sel = 2'd0;
    wire [8:0] maze_raddr;
    wire maze_rdata;
    wire signed [17:0] ball_x, ball_y;
    wire signed [11:0] vel_x, vel_y;
    wire phys_done, in_goal;

    integer sim_cycles = 0;
    integer errors = 0;
    integer max_latency = 0;
    integer latency;
    integer elapsed;
    integer generation_guard;
    integer frame_guard;
    integer bounce_seen;
    integer previous_velocity;
    integer current_velocity;
    integer n, seed_index, direction, f;

    always #5 clk = ~clk;
    always @(posedge clk) sim_cycles = sim_cycles + 1;

    maze_gen gen_i (
        .clk(clk), .rst(rst), .gen_start(gen_start), .n_cells(n_cells), .seed(seed),
        .gen_busy(gen_busy), .gen_done(gen_done), .we(maze_we), .waddr(maze_waddr),
        .wdata(maze_wdata), .start_col(start_col), .start_row(start_row),
        .goal_col(goal_col), .goal_row(goal_row)
    );

    maze_ram maze_i (
        .clk(clk), .we(maze_we), .waddr(maze_waddr), .wdata(maze_wdata),
        .raddr_p(maze_raddr), .rdata_p(maze_rdata), .ren_r(1'b0),
        .raddr_r(9'd0), .rdata_r()
    );

    ball_physics ball_i (
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .phys_init(phys_init), .phys_en(phys_en),
        .spawn_col(start_col), .spawn_row(start_row), .goal_col(goal_col), .goal_row(goal_row),
        .sin_q(sin_q), .cos_q(cos_q), .restitution_sel(restitution_sel),
        .maze_raddr(maze_raddr), .maze_rdata(maze_rdata),
        .ball_x(ball_x), .ball_y(ball_y), .vel_x(vel_x), .vel_y(vel_y),
        .phys_done(phys_done), .in_goal(in_goal)
    );

    task fail;
        input [511:0] message;
        begin
            $display("FAIL Story 3.4 frame budget: %0s (N=%0d seed=%h dir=%0d)",
                     message, n_cells, seed, direction);
            errors = errors + 1;
        end
    endtask

    task run_frame;
        begin
            @(negedge clk);
            latency = sim_cycles;
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
            frame_guard = 0;
            while (!phys_done && frame_guard < 200) begin
                @(negedge clk);
                frame_guard = frame_guard + 1;
            end
            elapsed = sim_cycles - latency;
            if (!phys_done) begin
                fail("phys_done did not arrive within the local timeout");
            end else begin
                if (elapsed > max_latency) max_latency = elapsed;
                if (elapsed >= VBLANK_BUDGET_CYCLES)
                    fail("physics update exceeded the 144000-cycle vertical-blank budget");
            end
        end
    endtask

    task run_case;
        input [3:0] maze_size;
        input [31:0] maze_seed;
        input integer move_right;
        begin
            n_cells = maze_size;
            seed = maze_seed;
            direction = move_right;
            sin_q = move_right ? 16'sd16384 : 16'sd0;
            cos_q = move_right ? 16'sd0 : 16'sd16384;
            rst = 1'b1;
            repeat (3) @(negedge clk);
            rst = 1'b0;
            @(negedge clk); gen_start = 1'b1;
            @(negedge clk); gen_start = 1'b0;
            generation_guard = 0;
            while (!gen_done && generation_guard < 100000) begin
                @(negedge clk);
                generation_guard = generation_guard + 1;
            end
            if (!gen_done) fail("maze generation timed out");
            @(negedge clk); phys_init = 1'b1;
            @(negedge clk); phys_init = 1'b0;
            repeat (3) @(negedge clk);

            bounce_seen = 0;
            previous_velocity = 0;
            for (f = 0; f < 48; f = f + 1) begin
                previous_velocity = move_right ? vel_x : vel_y;
                run_frame;
                current_velocity = move_right ? vel_x : vel_y;
                if (previous_velocity > 0 && current_velocity < 0)
                    bounce_seen = 1;
            end
            if (!bounce_seen) fail("outward gravity did not exercise an outer-wall collision");
        end
    endtask

    initial begin
        // Test both horizontal and vertical outer-wall collisions, two seeds,
        // and all supported stage sizes. maze_gen clears and rebuilds all 441 tiles.
        for (n = 2; n <= 10; n = n + 1) begin
            for (seed_index = 0; seed_index < 2; seed_index = seed_index + 1) begin
                run_case(n, 32'h3A11CE01 + seed_index * 32'h1020304, 0);
                run_case(n, 32'h3A11CE01 + seed_index * 32'h1020304, 1);
            end
        end

        if (errors == 0) begin
            $display("Story 3.4 frame budget: worst frame_tick-to-phys_done = %0d system clocks; budget = %0d; margin = %0d; cases = N=2..10, two seeds, horizontal/vertical outer-wall collision and free-flight frames",
                     max_latency, VBLANK_BUDGET_CYCLES, VBLANK_BUDGET_CYCLES - max_latency);
            $display("PASS: Story 3.4 physics frame budget");
        end else begin
            $display("FAIL: Story 3.4 frame budget had %0d errors; observed max latency %0d", errors, max_latency);
        end
        $finish;
    end

    initial begin
        #200000000;
        $display("FAIL: Story 3.4 frame-budget bench timed out");
        $finish;
    end
endmodule
