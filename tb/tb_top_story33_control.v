`timescale 1ns / 1ps

// End-to-end Story 3.3 control flow with abbreviated frame timing.
module tb_top_story33_control;
    localparam [1:0] MENU = 2'b00, GENERATE = 2'b01, PLAY = 2'b10, WIN = 2'b11;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;
    integer gen_start_count = 0;
    integer seed_capture_count = 0;
    integer phys_init_count = 0;
    integer guard, i, expected_x, expected_y;
    integer goal_left, goal_top;
    reg map_changed = 1'b0;
    reg [31:0] first_seed;
    reg [7:0] first_cfg;
    reg [440:0] first_map;
    reg signed [17:0] stopped_x, stopped_y;
    reg [11:0] stopped_angle;

    always #5 clk = ~clk;

    My_Top_Module #(
        .POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3), .WIN_HOLD_FRAMES(3)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnL(1'b0), .btnR(1'b0), .btnD(1'b0),
        .sw(16'h0000), .led(led), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    always @(posedge clk) begin
        if (!dut.rst) begin
            if (dut.gen_start) gen_start_count = gen_start_count + 1;
            if (dut.seed_capture) seed_capture_count = seed_capture_count + 1;
            if (dut.phys_init) phys_init_count = phys_init_count + 1;
        end
    end

    task fail;
        input [511:0] message;
        begin
            $display("FAIL Story 3.3 control: %0s (state=%b in_goal=%b)",
                     message, dut.game_state, dut.in_goal);
            $fatal(1);
        end
    endtask

    task wait_state;
        input [1:0] expected;
        begin
            guard = 0;
            while (dut.game_state !== expected && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (dut.game_state !== expected) fail("timed out waiting for game state");
        end
    endtask

    task pulse_frame;
        begin
            @(negedge clk);
            force dut.frame_tick = 1'b1;
            @(posedge clk); #1;
            force dut.frame_tick = 1'b0;
            repeat (6) @(negedge clk);
        end
    endtask

    task wait_gen_done;
        begin
            guard = 0;
            while (dut.gen_done !== 1'b1 && guard < 100000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (dut.gen_done !== 1'b1) fail("maze generation did not complete");
        end
    endtask

    task press_start;
        begin
            @(negedge clk); btnC = 1'b1;
            repeat (12) @(negedge clk);
            btnC = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b0;
        repeat (10) @(negedge clk);
        wait_state(MENU);

        press_start();
        pulse_frame();
        wait_state(GENERATE);
        wait_gen_done();
        first_seed = dut.seed;
        first_cfg = dut.active_game_cfg;
        pulse_frame();
        wait_state(PLAY);
        repeat (4) @(negedge clk);
        if (gen_start_count != 1 || seed_capture_count != 1 || phys_init_count != 1)
            fail("initial generation/start handoff counts are incorrect");
        for (i = 0; i < 441; i = i + 1)
            first_map[i] = dut.maze_ram_i.tile_mem[i];

        // Put only the ball centre at the generated goal. Confirm the actual
        // physics detector, rather than forcing game_ctrl.in_goal.
        goal_left = dut.goal_col * 4096 - 43008;
        goal_top = dut.goal_row * 4096 - 43008;
        force dut.ball_i.ball_x = goal_left + 2048;
        force dut.ball_i.ball_y = goal_top + 2048;
        #1;
        if (dut.in_goal !== 1'b1) fail("connected detector missed goal-tile centre");

        // A high goal level alone cannot change state; the frame boundary does.
        repeat (2) @(negedge clk);
        if (dut.game_state !== PLAY) fail("goal bypassed the frame boundary");
        pulse_frame();
        wait_state(WIN);
        release dut.ball_i.ball_x;
        release dut.ball_i.ball_y;
        repeat (8) @(negedge clk);
        if (!dut.render_i.win_frame || dut.phys_en || dut.angle_rot_cmd !== 2'sd0)
            fail("WIN did not preserve the visual state while freezing gameplay");
        stopped_x = dut.ball_x;
        stopped_y = dut.ball_y;
        stopped_angle = dut.angle;
        force dut.rot_cmd = 2'sd1;

        pulse_frame();
        if (dut.game_state !== WIN || gen_start_count != 1 || !dut.render_i.win_frame)
            fail("WIN did not persist through the first hold frame");
        if (dut.angle_rot_cmd !== 2'sd0 || dut.angle !== stopped_angle)
            fail("maze rotation was not frozen during WIN");
        pulse_frame();
        if (dut.game_state !== WIN || gen_start_count != 1 || !dut.render_i.win_frame)
            fail("WIN did not persist through the second hold frame");
        if (dut.angle_rot_cmd !== 2'sd0 || dut.angle !== stopped_angle)
            fail("maze rotation changed before the WIN interval ended");
        if (dut.ball_x !== stopped_x || dut.ball_y !== stopped_y)
            fail("ball moved while WIN was held");
        pulse_frame();
        release dut.rot_cmd;
        wait_state(GENERATE);
        guard = 0;
        while (gen_start_count < 2 && guard < 50) begin
            @(negedge clk); guard = guard + 1;
        end
        if (gen_start_count != 2 || seed_capture_count != 2)
            fail("WIN timeout did not issue exactly one fresh generation request");
        if (dut.active_game_cfg !== first_cfg)
            fail("automatic replay changed the active stage/rotation configuration");
        if (dut.seed === first_seed) fail("non-debug replay reused the previous seed");

        wait_gen_done();
        for (i = 0; i < 441; i = i + 1) begin
            if (dut.maze_ram_i.tile_mem[i] !== first_map[i]) begin
                map_changed = 1'b1;
            end
        end
        if (!map_changed) fail("new seed produced the same maze image");

        pulse_frame();
        wait_state(PLAY);
        repeat (5) @(negedge clk);
        expected_x = (dut.start_col - 10) * 4096;
        expected_y = (dut.start_row - 10) * 4096;
        if ($signed(dut.ball_x) !== expected_x || $signed(dut.ball_y) !== expected_y)
            fail("new game did not respawn the ball at the red start centre");
        if (dut.in_goal || dut.render_i.win_frame)
            fail("new game retained the WIN indication or spawned in the goal");
        if (gen_start_count != 2 || seed_capture_count != 2 || phys_init_count != 2)
            fail("replay did not perform exactly one generation and ball initialization");
        if (dut.active_game_cfg !== first_cfg) fail("active configuration changed after replay");

        release dut.frame_tick;
        $display("PASS: Story 3.3 goal detector, frame-safe WIN, three-frame test hold, fresh maze, retained config, and red-start respawn");
        $finish;
    end

    initial begin
        #20000000;
        fail("testbench timeout");
    end
endmodule
