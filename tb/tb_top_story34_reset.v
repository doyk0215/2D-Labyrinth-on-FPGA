`timescale 1ns / 1ps

module tb_top_story34_reset;
    localparam [1:0] MENU = 2'b00, GENERATE = 2'b01, PLAY = 2'b10, WIN = 2'b11;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    reg btnU = 1'b0;
    reg btnL = 1'b0;
    reg btnR = 1'b0;
    reg btnD = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;
    integer errors = 0;
    integer guard;
    integer gen_start_count = 0;
    integer phys_init_count = 0;
    reg [31:0] first_seed;

    always #5 clk = ~clk;

    My_Top_Module #(
        .SNAP_DEBOUNCE_CYCLES(2), .MENU_DEBOUNCE_CYCLES(2), .POR_CYCLES(2),
        .WIN_HOLD_FRAMES(3), .TIMER_CLK_HZ(10)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR),
        .btnD(btnD), .sw(16'h0000), .led(led),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    always @(posedge clk) begin
        if (!dut.rst) begin
            if (dut.gen_start) gen_start_count = gen_start_count + 1;
            if (dut.phys_init) phys_init_count = phys_init_count + 1;
        end
    end

    task fail;
        input [511:0] message;
        begin
            $display("FAIL Story 3.4 reset: %0s (state=%b)", message, dut.game_state);
            errors = errors + 1;
        end
    endtask

    task wait_state;
        input [1:0] expected;
        begin
            guard = 0;
            while (dut.game_state !== expected && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (dut.game_state !== expected) fail("timed out waiting for game state");
        end
    endtask

    task wait_gen_done;
        begin
            guard = 0;
            while (dut.gen_done !== 1'b1 && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (dut.gen_done !== 1'b1) fail("maze generation did not complete");
        end
    endtask

    task pulse_frame;
        begin
            @(negedge clk); force dut.frame_tick = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); force dut.frame_tick = 1'b0;
            repeat (8) @(negedge clk);
        end
    endtask

    task press_confirm;
        begin
            @(negedge clk); btnC = 1'b1;
            repeat (12) @(negedge clk);
            btnC = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    task press_up;
        begin
            @(negedge clk); btnU = 1'b1;
            repeat (12) @(negedge clk);
            btnU = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    task press_settings;
        begin
            @(negedge clk); btnL = 1'b1;
            repeat (12) @(negedge clk);
            btnL = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    task press_reset;
        begin
            press_confirm;
            repeat (4) @(negedge clk);
        end
    endtask

    task start_until_generate;
        begin
            press_confirm;
            pulse_frame;
            wait_state(GENERATE);
        end
    endtask

    task finish_start;
        begin
            wait_gen_done;
            pulse_frame;
            wait_state(PLAY);
            repeat (3) @(negedge clk);
        end
    endtask

    task check_clean_menu;
        begin
            if (dut.game_state !== MENU || dut.gen_busy || dut.gen_done || dut.gen_start || dut.phys_init)
                fail("reset left a generation or physics handoff active");
            if (dut.angle !== 12'd0 || dut.ball_x !== 18'sd0 || dut.ball_y !== 18'sd0 ||
                dut.ball_vx !== 12'sd0 || dut.ball_vy !== 12'sd0)
                fail("reset did not clear angle, position, and velocity");
            if (dut.ball_i.gx_frac !== 20'd0 || dut.ball_i.gy_frac !== 20'd0 ||
                dut.angle_i.pending_valid !== 1'b0 || dut.angle_i.phase_remainder !== 6'd0)
                fail("reset did not clear physics fractions or angle pending state");
            if (dut.elapsed_minutes_bcd !== 8'h00 || dut.elapsed_seconds_bcd !== 8'h00)
                fail("reset did not clear the elapsed timer");
            if (dut.status_text[7:0] !== "S")
                fail("reset did not restore the OLED stage menu");
            if (dut.game_cfg[7:6] !== 2'b10)
                fail("in-game reset did not retain the FAST rotation setting");
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b0;
        repeat (12) @(negedge clk);
        wait_state(MENU);

        // Set FAST, return to the stage menu, then confirm starts the selected game.
        press_settings;
        press_up;
        press_confirm;
        if (dut.game_cfg[7:6] !== 2'b10) fail("settings selection did not reach game_cfg");

        // Interrupt generation with reset. The generator and controller must both abort.
        start_until_generate;
        guard = 0;
        while (!dut.gen_busy && guard < 50) begin @(negedge clk); guard = guard + 1; end
        if (!dut.gen_busy) fail("maze generator did not enter its busy state");
        press_reset;
        check_clean_menu;
        repeat (10) @(negedge clk);
        if (dut.gen_done || dut.gen_busy || dut.gen_start) fail("aborted generation produced stale completion");

        // Confirming after reset performs one new generation and waits for its frame handoff.
        start_until_generate;
        finish_start;
        first_seed = dut.seed;
        if (gen_start_count != 2 || phys_init_count != 1)
            fail("restart after GENERATE reset did not perform exactly one fresh start");
        if ($signed(dut.ball_x) !== ((dut.start_col - 10) * 4096) ||
            $signed(dut.ball_y) !== ((dut.start_row - 10) * 4096) ||
            dut.ball_vx !== 0 || dut.ball_vy !== 0)
            fail("new game did not initialize the ball at rest on the red start tile");

        // Create visible nonzero runtime state before resetting PLAY.
        force dut.angle_rot_cmd = 2'sd1;
        pulse_frame;
        release dut.angle_rot_cmd;
        guard = 0;
        while (!dut.phys_done && guard < 100) begin @(negedge clk); guard = guard + 1; end
        repeat (20) @(negedge clk);
        if (dut.angle == 0 || (dut.ball_vx == 0 && dut.ball_vy == 0) || dut.elapsed_seconds_bcd == 0)
            fail("PLAY setup did not exercise angle, physics, and timer state");

        press_reset;
        check_clean_menu;
        if (gen_start_count != 2) fail("PLAY reset unexpectedly started a maze");

        // Reset during WIN cancels the automatic replay countdown.
        start_until_generate;
        finish_start;
        force dut.in_goal = 1'b1;
        pulse_frame;
        release dut.in_goal;
        wait_state(WIN);
        press_reset;
        check_clean_menu;
        if (gen_start_count != 3) fail("WIN reset did not cancel the pending automatic replay");

        // Starting again after a WIN reset makes a fresh maze and retains the rate.
        start_until_generate;
        finish_start;
        if (gen_start_count != 4 || phys_init_count != 3)
            fail("restart after WIN reset did not make exactly one clean game");
        if (dut.active_game_cfg[7:6] !== 2'b10 || dut.active_game_cfg[3:0] !== 4'd5)
            fail("restart lost the selected rotation rate or reset stage selection");
        if (dut.seed === first_seed) fail("post-reset start did not capture a fresh non-debug seed");

        release dut.frame_tick;
        if (errors == 0)
            $display("PASS: Story 3.4 reset from GENERATE, PLAY, and WIN; fresh generation, clean respawn, timer/angle/physics clear, and settings retention");
        else
            $display("FAIL: Story 3.4 reset integration had %0d errors", errors);
        $finish;
    end

    initial begin
        #100000000;
        fail("testbench timeout");
        $finish;
    end
endmodule
