`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_top_story62_reset;
    reg clk = 0, btnC = 0, btnU = 0, btnD = 0, btnL = 0;
    always #5 clk = ~clk;
    tri1 ps2_clk, ps2_data;
    wire oled_res, oled_vbatc, oled_vddc;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3),
        .LONG_PRESS_CYCLES(64), .TIMER_CLK_HZ(32), .WIN_HOLD_FRAMES(3)) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(1'b0),
        .sw(16'h0001), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );
    // Only this integration bench scales the supplied driver's delay/frame
    // counters. The nominal-frequency SPI/power timing tests remain unchanged.
    defparam dut.oled_i.ClkFreq = 62500;

    // Legacy auto-start is a debug option: even there full reset must land in
    // MENU without starting a stage. Keep ordinary rst's legacy behavior.
    game_ctrl #(.START_IN_MENU(1'b0)) legacy_ctrl_i (
        .clk(clk), .rst(dut.rst), .full_reset(dut.full_reset), .frame_tick(1'b1),
        .start_game(1'b0), .game_cfg(8'h05), .regen_button(1'b0),
        .gen_busy(1'b0), .gen_done(1'b0), .in_goal(1'b0), .game_state()
    );
    integer short_count = 0, starts = 0, oled_resets = 0, oled_display_offs = 0;
    reg [4:0] previous_oled_state = 0;
    always @(posedge clk) begin
        if (dut.btnC_press) short_count = short_count + 1;
        if (dut.gen_start) starts = starts + 1;
    end
    always @(negedge oled_res) oled_resets = oled_resets + 1;
    always @(posedge dut.clk_6m25) begin
        if (dut.oled_i.state == dut.oled_i.DisplayOff &&
            previous_oled_state != dut.oled_i.DisplayOff)
            oled_display_offs = oled_display_offs + 1;
        previous_oled_state = dut.oled_i.state;
    end
    task fail;
        input [767:0] message;
        begin $display("FAIL Story 6.2: %0s (state=%b)", message, dut.game_state); $fatal(1); end
    endtask
    task cycles;
        input integer count;
        begin repeat (count) @(negedge clk); #1; end
    endtask
    task frame;
        begin force dut.frame_tick = 1'b1; cycles(1);
            force dut.frame_tick = 1'b0; cycles(5); end
    endtask
    task click;
        input integer id;
        begin
            case (id) 0: btnC = 1; 1: btnU = 1; 2: btnD = 1; 3: btnL = 1; endcase
            cycles(12);
            case (id) 0: btnC = 0; 1: btnU = 0; 2: btnD = 0; 3: btnL = 0; endcase
            cycles(12);
        end
    endtask
    task oled_ready;
        integer guard;
        begin
            guard = 0;
            while ((dut.oled_i.state != dut.oled_i.WaitNextFrame &&
                    dut.oled_i.state != dut.oled_i.SendPixel) && guard < 500000) begin
                cycles(1); guard = guard + 1;
            end
            if (guard == 500000 || !oled_vddc || !oled_vbatc) fail("OLED did not complete startup");
            force dut.oled_frame_begin = 1'b1;
            cycles(80); release dut.oled_frame_begin;
            if (dut.text_active[7:0] !== "S") fail("OLED mailbox retained a pre-reset page");
        end
    endtask
    task start_play;
        integer guard;
        begin
            click(0); frame();
            guard = 0;
            while (!dut.gen_done && guard < 50000) begin cycles(1); guard = guard + 1; end
            if (guard == 50000) fail("maze generation timeout");
            cycles(4); frame();
            if (dut.game_state !== `ST_PLAY) fail("short release did not start PLAY");
        end
    endtask
    task long_reset;
        integer before_shorts, before_starts, before_oled_resets, before_display_offs, guard;
        begin
            before_shorts = short_count;
            before_oled_resets = oled_resets;
            before_display_offs = oled_display_offs;
            // Dirty mouse activity bookkeeping so its reset is observable.
            force dut.mouse_event = 1'b1; cycles(2); release dut.mouse_event;
            if (!dut.mouse_connected) fail("mouse reset precondition missing");
            btnC = 1;
            guard = 0;
            while (!dut.full_reset && guard < 100) begin cycles(1); guard = guard + 1; end
            if (guard == 100) fail("long press did not assert full reset");
            cycles(80);
            if (!dut.full_reset || !dut.rst || dut.game_state !== `ST_MENU ||
                legacy_ctrl_i.game_state !== `ST_MENU || dut.phys_en || dut.gen_busy || dut.gen_start ||
                dut.angle !== 0 || dut.elapsed_seconds_bcd !== 0 || dut.elapsed_minutes_bcd !== 0)
                fail("full reset did not clear game/control state into MENU");
            if (dut.game_cfg !== 8'h05 || dut.active_game_cfg !== 8'h05 ||
                dut.menu_ctrl_i.settings_page || dut.menu_ctrl_i.selected_stage)
                fail("full reset retained the stage or rotation settings");
            if (dut.mouse_controller.rst !== 1'b1 || dut.mouse_connected || dut.mouse_event_timer ||
                dut.mouse_left || dut.mouse_right || dut.mouse_middle)
                fail("full reset missed the real PS/2 mouse path");
            if (!dut.oled_reset || oled_vddc || oled_vbatc ||
                dut.oled_i.state !== dut.oled_i.PowerUp || dut.text_active !== 0 ||
                dut.text_pending_valid || dut.text_ack_toggle || dut.text_req_toggle !== 1'b1)
                fail("OLED startup/mailbox were not reset");
            before_starts = starts;
            cycles(160);
            if (!dut.full_reset || short_count != before_shorts || starts != before_starts)
                fail("long hold triggered a short action or started a stage");
            btnC = 0; cycles(160);
            if (dut.full_reset || dut.rst || dut.game_state !== `ST_MENU ||
                short_count != before_shorts || starts != before_starts)
                fail("long release confirmed a stage or did not return to MENU");
            oled_ready();
            if (oled_resets <= before_oled_resets || oled_display_offs <= before_display_offs)
                fail("OLED failed to repeat reset-pin and initialization-command phases");
            if (dut.game_state !== `ST_MENU || starts != before_starts)
                fail("stage started after full-reset recovery");
        end
    endtask
    initial begin
        force dut.frame_tick = 1'b0;
        cycles(20); oled_ready();
        // MENU: reset nondefault stage/speed and an open settings page.
        click(1); click(3); click(1);
        if (dut.game_cfg === 8'h05 || !dut.menu_ctrl_i.settings_page)
            fail("MENU reset preconditions were not established");
        long_reset();
        $display("Story 6.2: long reset from MENU passed");

        // No action while CENTER is down; exactly one confirm on short release.
        btnC = 1; cycles(12); frame();
        if (dut.game_state !== `ST_MENU || dut.start_game) fail("CENTER press acted before release");
        btnC = 0; cycles(12); frame();
        if (dut.game_state !== `ST_GENERATE) fail("short release failed to confirm");
        click(0);
        if (dut.game_state !== `ST_MENU) fail("short release failed to return from GENERATE");
        click(0); frame();
        if (dut.game_state !== `ST_GENERATE) fail("GENERATION reset precondition missing");
        long_reset();
        $display("Story 6.2: long reset from GENERATE passed");

        click(3); click(1); click(0); // FAST, then leave settings
        if (dut.game_cfg[7:6] !== 2'b10) fail("rotation preference precondition missing");
        start_play(); cycles(100);
        if (dut.elapsed_seconds_bcd === 0) fail("PLAY timer reset precondition missing");
        // Short return preserves the configured speed, unlike a full reset.
        click(0);
        if (dut.game_state !== `ST_MENU || dut.game_cfg[7:6] !== 2'b10)
            fail("short return lost the rotation preference");
        start_play();
        btnL = 1; cycles(6); frame(); btnL = 0; cycles(6);
        if (dut.angle === 0) fail("angle reset precondition missing");
        long_reset();
        $display("Story 6.2: long reset from PLAY passed");

        start_play();
        force dut.in_goal = 1'b1; frame(); release dut.in_goal;
        if (dut.game_state !== `ST_WIN) fail("WIN reset precondition missing");
        click(0);
        if (dut.game_state !== `ST_MENU) fail("short release failed to return from WIN");
        start_play();
        force dut.in_goal = 1'b1; frame(); release dut.in_goal;
        if (dut.game_state !== `ST_WIN) fail("second WIN reset precondition missing");
        long_reset();
        $display("Story 6.2: long reset from WIN passed");
        start_play();
        if (dut.game_state !== `ST_PLAY) fail("short press did not re-arm after repeated full resets");
        $display("PASS: Story 6.2 long reset from all states, exclusive short release, defaults, mouse, and OLED restart");
        $finish;
    end
    initial begin #30000000; fail("timeout"); end
endmodule
