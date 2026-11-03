`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_menu_background;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg btnC = 1'b0, btnL = 1'b0, btnR = 1'b0;
    wire [3:0] vga_r, vga_g, vga_b;
    tri1 ps2_clk, ps2_data;

    My_Top_Module #(
        .POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3), .LONG_PRESS_CYCLES(1000)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnL(btnL), .btnR(btnR), .btnD(1'b0),
        .sw(16'd0), .led(), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(), .vga_vs(), .seg(), .dp(), .an(), .ps2_clk(ps2_clk),
        .ps2_data(ps2_data), .oled_cs(), .oled_mosi(), .oled_sclk(), .oled_dc(),
        .oled_res(), .oled_vbatc(), .oled_vddc()
    );

    integer guard;
    reg [31:0] saved_seed;

    task fail;
        input [8*100-1:0] message;
        begin
            $display("FAIL menu background: %0s state=%b ready=%b seed=%h",
                     message, dut.game_state, dut.menu_bg_ready, dut.seed);
            $fatal(1);
        end
    endtask

    task wait_ready;
        begin
            guard = 0;
            while (!dut.menu_bg_ready && guard < 50000) begin
                @(negedge clk); guard = guard + 1;
            end
            if (!dut.menu_bg_ready) fail("menu maze generation timeout");
        end
    endtask

    task press_centre;
        begin
            @(negedge clk); btnC = 1'b1;
            repeat (12) @(negedge clk);
            btnC = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    task press_left;
        begin
            @(negedge clk); btnL = 1'b1;
            repeat (10) @(negedge clk);
            btnL = 1'b0;
            repeat (10) @(negedge clk);
        end
    endtask

    task press_right;
        begin
            @(negedge clk); btnR = 1'b1;
            repeat (10) @(negedge clk);
            btnR = 1'b0;
            repeat (10) @(negedge clk);
        end
    endtask

    task wait_for_start;
        begin
            guard = 0;
            while (!dut.game_ctrl_i.start_pending && guard < 100) begin
                @(negedge clk); guard = guard + 1;
            end
            if (!dut.game_ctrl_i.start_pending) fail("start selection was not accepted");
        end
    endtask

    task pulse_frame;
        begin
            @(negedge clk); force dut.frame_tick = 1'b1;
            @(negedge clk); force dut.frame_tick = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    task wait_game_state;
        input [`GAME_STATE_W-1:0] expected_state;
        begin
            guard = 0;
            while ((dut.game_state !== expected_state) && guard < 50000) begin
                @(negedge clk); guard = guard + 1;
            end
            if (dut.game_state !== expected_state) fail("game-state timeout");
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b0;
        wait_game_state(`ST_MENU);
        wait_ready();
        if (dut.render_cam_x !== 18'sd0 || dut.render_cam_y !== 18'sd0 ||
            dut.render_sin_q !== 16'sd0 || dut.render_cos_q !== 16'sd16923)
            fail("menu maze was not configured for centered, unrotated rendering");
        saved_seed = dut.seed;

        press_left();
        if (!dut.settings_page || !dut.menu_bg_ready || dut.seed !== saved_seed)
            fail("entering Settings changed the menu maze");
        press_centre();
        guard = 0;
        while (dut.settings_page && guard < 100) begin
            @(negedge clk); guard = guard + 1;
        end
        wait_ready();
        if (dut.seed === saved_seed) fail("returning from Settings reused the maze seed");
        saved_seed = dut.seed;

        press_right();
        if (!dut.instructions_active || !dut.menu_bg_ready)
            fail("Instructions page did not open over the current maze");
        press_centre();
        guard = 0;
        while (dut.instructions_active && guard < 100) begin
            @(negedge clk); guard = guard + 1;
        end
        wait_ready();
        if (dut.seed === saved_seed) fail("returning from Instructions reused the maze seed");

        // Start a game and return to MENU with the normal short BTNC action.
        press_centre();
        wait_for_start();
        pulse_frame();
        wait_game_state(`ST_GENERATE);
        guard = 0;
        while (!dut.gen_done && guard < 50000) begin
            @(negedge clk); guard = guard + 1;
        end
        if (!dut.gen_done) fail("game maze generation timeout");
        pulse_frame();
        wait_game_state(`ST_PLAY);
        saved_seed = dut.seed;
        press_centre();
        wait_game_state(`ST_MENU);
        wait_ready();
        if (dut.seed === saved_seed) fail("quitting the game reused the game maze seed");

        $display("PASS: menu maze is centered and receives a fresh seed after Settings, Instructions, and game quit");
        $finish;
    end

    initial begin
        #10000000;
        fail("test timeout");
    end
endmodule
