`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_top_story82_countdown;
    reg clk=0, btnC=0, btnR=0;
    reg [15:0] sw=16'h4000;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(2),
        .SNAP_DEBOUNCE_CYCLES(2), .LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(256), .EASY_TIME_SECONDS(3), .HARD_TIME_SECONDS(4),
        .HUGE_TIME_SECONDS(5), .WIN_HOLD_FRAMES(2), .LOSE_HOLD_FRAMES(3)) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnD(1'b0), .btnL(1'b0),
        .btnR(btnR), .sw(sw), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail;
        input [767:0] msg;
        begin $display("FAIL Story 8.2: %0s state=%0d time=%02h:%02h",msg,dut.game_state,
                       dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd); $fatal(1); end
    endtask
    task cycles;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task frame;
        begin force dut.frame_tick=1; cycles(1); force dut.frame_tick=0; cycles(4); end
    endtask
    task click;
        begin btnC=1; cycles(12); btnC=0; cycles(12); end
    endtask
    task finish_generation;
        integer guard;
        begin
            guard=0;
            while(!dut.gen_done && guard<200000) begin cycles(1); guard=guard+1; end
            if(guard==200000) fail("generation timeout");
            // PLAY can begin after generation, but countdown waits until the
            // maze has a scanout pixel and the player makes a control input.
            force dut.active_video=1'b0;
            force dut.frame_tick=1; cycles(1);
            force dut.frame_tick=0; cycles(1);
            if(dut.game_state !== `ST_PLAY || dut.elapsed_seconds_bcd !== 8'h03 ||
               dut.elapsed_timer_i.play_started)
                fail("timer armed before visible video began");
            cycles(3);
            if(dut.elapsed_timer_i.play_started || dut.elapsed_seconds_bcd !== 8'h03)
                fail("timer started while the generated maze was still blanked");
            force dut.maze_pixel_visible=1'b0;
            force dut.timer_player_action=1'b1;
            if(dut.elapsed_timer_i.play_started || dut.elapsed_seconds_bcd !== 8'h03)
                fail("player action before maze visibility started the timer");
            cycles(2);
            if(dut.elapsed_timer_i.play_started)
                fail("player action without maze content started the timer");
            force dut.timer_player_action=1'b0;
            force dut.maze_pixel_visible=1'b1;
            cycles(2);
            if(dut.elapsed_timer_i.play_started)
                fail("visible maze started the timer without player action");
            force dut.timer_player_action=1'b1;
            cycles(2);
            if(!dut.elapsed_timer_i.play_started || dut.elapsed_seconds_bcd !== 8'h03)
                fail("timer did not arm on first player action with the maze visible");
            release dut.maze_pixel_visible;
            release dut.timer_player_action;
            release dut.active_video;
            cycles(16);
            if(dut.elapsed_seconds_bcd !== 8'h03)
                fail("countdown changed before one second of visible PLAY");
        end
    endtask
    task start;
        begin click(); frame();
            if(dut.game_state !== `ST_GENERATE) fail("menu confirm failed");
            finish_generation(); end
    endtask
    task expire;
        integer guard;
        begin
            guard=0;
            while(dut.elapsed_seconds_bcd != 0 && guard<2000) begin cycles(1); guard=guard+1; end
            if(guard==2000 || !dut.time_up) fail("timer did not naturally reach zero");
            if(dut.game_state !== `ST_PLAY) fail("timeout changed state before frame boundary");
            frame();
            if(dut.game_state !== `ST_LOSE || dut.phys_en) fail("expiry did not enter LOSE with physics disabled");
            // Finish any step that started on the entry edge before taking
            // the frozen-state snapshot, just as the real blanking allows.
            cycles(100);
        end
    endtask
    reg [11:0] frozen_angle;
    reg signed [17:0] frozen_x,frozen_y;
    reg signed [11:0] frozen_vx,frozen_vy;
    integer mode;
    initial begin
        force dut.frame_tick=0; cycles(16);
        for(mode=0;mode<2;mode=mode+1) begin
            sw[15]=mode; cycles(8); start();
            btnR=1; cycles(8); frame(); btnR=0; cycles(8); frame();
            expire();
            frozen_angle=dut.angle; frozen_x=dut.ball_x; frozen_y=dut.ball_y;
            frozen_vx=dut.ball_vx; frozen_vy=dut.ball_vy;
            btnR=1; cycles(8); btnR=0; cycles(8);
            frame(); frame();
            if(dut.game_state !== `ST_LOSE || dut.angle !== frozen_angle ||
               dut.ball_x !== frozen_x || dut.ball_y !== frozen_y ||
               dut.ball_vx !== frozen_vx || dut.ball_vy !== frozen_vy ||
               dut.gen_start || dut.phys_init || dut.elapsed_seconds_bcd !== 0)
                fail("LOSE hold moved physics/rotation, underflowed, or replayed");
            frame();
            if(dut.game_state !== `ST_MENU) fail("LOSE did not return to MENU after exactly three frames");
            frame(); if(dut.game_state !== `ST_MENU) fail("stale start automatically left MENU");
        end
        // A win with remaining time keeps Story 3.3 replay and reloads timer.
        start(); force dut.in_goal=1; frame(); release dut.in_goal;
        if(dut.game_state !== `ST_WIN) fail("pre-deadline goal did not win");
        cycles(1000);
        if(dut.elapsed_seconds_bcd !== 8'h03) fail("WIN countdown did not freeze");
        frame(); frame();
        if(dut.game_state !== `ST_GENERATE) fail("WIN did not automatically replay");
        finish_generation();
        // A late goal and a regeneration request cannot override timeout.
        cycles(768); force dut.in_goal=1; force dut.regen_request=1; frame();
        release dut.in_goal; release dut.regen_request;
        if(dut.game_state !== `ST_LOSE) fail("late goal or regenerate beat timeout");
        click();
        if(dut.game_state !== `ST_MENU || dut.elapsed_seconds_bcd !== 0) fail("short reset from LOSE failed");
        // Goal on the exact terminal timer edge must lose as well.
        start();
        wait(dut.elapsed_seconds_bcd == 1 && dut.elapsed_timer_i.subsecond_count == 255);
        @(negedge clk);
        if(!dut.time_up) fail("terminal-edge precondition missing");
        force dut.in_goal=1; frame(); release dut.in_goal;
        if(dut.game_state !== `ST_LOSE || dut.elapsed_seconds_bcd !== 0)
            fail("goal on the exact deadline incorrectly won");
        btnC=1; cycles(96);
        if(!dut.full_reset || dut.game_state !== `ST_MENU || dut.elapsed_seconds_bcd !== 0)
            fail("long reset from LOSE failed");
        btnC=0; cycles(20); frame();
        if(dut.game_state !== `ST_MENU) fail("long release started a stage");
        $display("PASS: Story 8.2 top countdown, frame-boundary LOSE, smooth/snap freeze, hold, replay and reset");
        $finish;
    end
    initial begin #20000000; fail("timeout"); end
endmodule
