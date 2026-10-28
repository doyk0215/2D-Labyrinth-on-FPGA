`timescale 1ns / 1ps

// CJX's Story 3.3 integration uses the existing controller's WIN input as a
// simulation stub. Goal detection and the two-second pause remain QZ's work.
module tb_top_win_indication;
    reg clk = 1'b0, btnC = 1'b0;
    always #5 clk = ~clk;
    wire [3:0] r, g, b;
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3)) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnD(1'b0), .btnL(1'b0), .btnR(1'b0),
        .sw(16'h0001), .led(), .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(), .vga_vs(),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data), .oled_cs(), .oled_mosi(), .oled_sclk(),
        .oled_dc(), .oled_res(), .oled_vbatc(), .oled_vddc()
    );
    task fail;
        input [511:0] message;
        begin $display("FAIL top win: %0s (state=%b RGB=%h)", message, dut.game_state, {r,g,b}); $fatal(1); end
    endtask
    task wait_state;
        input [1:0] state;
        integer guard;
        begin
            guard = 0;
            while (dut.game_state !== state && guard < 20000) begin
                @(negedge clk); guard = guard + 1;
            end
            if (dut.game_state !== state) fail("state transition timeout");
        end
    endtask
    task press_centre;
        begin
            @(negedge clk); btnC = 1'b1;
            repeat (12) @(negedge clk); btnC = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask
    reg [9:0] probe_x, probe_y;
    task check_pixel;
        input [9:0] x, y;
        input [11:0] colour;
        begin
            @(negedge clk); probe_x = x; probe_y = y;
            force dut.pixel_x = probe_x;
            force dut.pixel_y = probe_y;
            repeat (2) @(negedge clk);
            if ({r,g,b} !== colour) fail("WIN display masked or stale pixel after transition");
        end
    endtask
    task frame;
        begin
            @(negedge clk); force dut.frame_tick = 1'b1;
            @(negedge clk); force dut.frame_tick = 1'b0;
            repeat (5) @(negedge clk);
        end
    endtask
    reg signed [17:0] stopped_x, stopped_y;
    initial begin
        force dut.frame_tick = 1'b1;
        force dut.active_video = 1'b1;
        force dut.ball_on = 1'b1; // contrasting underlay checks win priority
        repeat (20) @(negedge clk);
        wait_state(2'b00);
        check_pixel(156,212,12'h002); // MENU masks even a forced ball
        press_centre();
        wait_state(2'b10);
        force dut.frame_tick = 1'b0;
        repeat (10) @(negedge clk);
        check_pixel(156,212,12'hfc0);

        force dut.game_ctrl_i.in_goal = 1'b1;
        frame();
        wait_state(2'b11);
        force dut.game_ctrl_i.in_goal = 1'b0;
        if (!dut.render_enable_d || !dut.maze_ram_i.ren_r || dut.phys_en)
            fail("WIN must retain render reads and disable physics");
        check_pixel(13,13,12'h0f0);
        check_pixel(156,212,12'hfff);
        check_pixel(140,200,12'h013);
        check_pixel(100,100,12'hfc0); // unoccluded scene remains present
        repeat (20) @(negedge clk);
        stopped_x = dut.ball_x; stopped_y = dut.ball_y;
        repeat (20) @(negedge clk);
        if (dut.ball_x !== stopped_x || dut.ball_y !== stopped_y) fail("physics moved in WIN");

        // Current control skeleton resumes generation on its next frame.
        // The display must disappear immediately while the new map is written.
        frame();
        wait_state(2'b01);
        if (dut.maze_ram_i.ren_r || dut.render_enable_d) fail("render reads enabled in GENERATE");
        check_pixel(156,212,12'h002);
        wait (dut.gen_done === 1'b1);
        repeat (3) @(negedge clk);
        frame();
        wait_state(2'b10);
        check_pixel(156,212,12'hfc0);

        // A second WIN followed by the real debounced reset returns to MENU
        // without keeping a banner or enabling renderer reads there.
        force dut.game_ctrl_i.in_goal = 1'b1;
        frame();
        wait_state(2'b11);
        force dut.game_ctrl_i.in_goal = 1'b0;
        check_pixel(156,212,12'hfff);
        press_centre();
        wait_state(2'b00);
        if (dut.maze_ram_i.ren_r || dut.render_i.win_frame) fail("reset retained win state");
        check_pixel(156,212,12'h002);
        release dut.game_ctrl_i.in_goal;
        $display("PASS: top win indication, WIN render reads, frozen physics, regeneration clearing, and menu reset");
        $finish;
    end
    initial begin #1000000; fail("timeout"); end
endmodule
