`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Real menu/generator/countdown/controller and OLED CDC mailbox. Frame
// boundaries and second duration are shortened; timer expiry is never forced.
module tb_top_story83_time_up;
    reg clk=0, btnC=0, btnD=0, btnR=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(2),
        .LONG_PRESS_CYCLES(64), .SNAP_DEBOUNCE_CYCLES(2),
        .TIMER_CLK_HZ(1024), .EASY_TIME_SECONDS(2), .HARD_TIME_SECONDS(3),
        .LOSE_HOLD_FRAMES(3)) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnD(btnD), .btnL(1'b0),
        .btnR(btnR), .sw(16'h0001), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail;
        input [767:0] message;
        begin $display("FAIL Story 8.3 top: %0s (state=%0d)",message,dut.game_state); $fatal(1); end
    endtask
    task cycles;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task frame;
        begin force dut.frame_tick=1; cycles(1); force dut.frame_tick=0; cycles(8); end
    endtask
    task click;
        input integer down;
        begin
            if(down) btnD=1; else btnC=1;
            cycles(12);
            btnC=0; btnD=0; cycles(12);
        end
    endtask
    task player_action;
        begin
            // The Story 8.2 timer waits for both a visible maze pixel and the
            // first player action. Force the visibility qualifier here so
            // this timeout integration bench does not need to simulate a
            // complete 800x525 VGA scan before its short timer can start.
            force dut.maze_pixel_visible=1'b1;
            btnR=1; cycles(8); btnR=0; cycles(8);
            release dut.maze_pixel_visible;
        end
    endtask
    task oled_snapshot;
        integer guard;
        reg [511:0] old_page;
        begin
            old_page=dut.text_active;
            force dut.oled_frame_begin=0;
            guard=0;
            while((!dut.text_pending_valid || dut.text_pending !== dut.status_text ||
                   dut.text_req_toggle != dut.text_ack_sync[1]) && guard<1000) begin
                cycles(1); guard=guard+1;
            end
            if(guard==1000) fail("new status failed to reach pending OLED buffer");
            if(dut.text_active !== old_page) fail("OLED status tore before frame_begin");
            force dut.oled_frame_begin=1; cycles(64); force dut.oled_frame_begin=0;
            if(dut.text_active !== dut.status_text) fail("OLED did not capture whole new page at its frame boundary");
        end
    endtask
    task start;
        input integer hard;
        integer guard;
        begin
            // Timeout returns to the menu without resetting its selection.
            // Navigate from the retained selection instead of assuming EASY.
            guard=0;
            while(dut.menu_ctrl_i.selected_stage !== (hard ? 2'd1 : 2'd0) && guard<3) begin
                click(1); guard=guard+1;
            end
            if(guard==3) fail("could not select the requested stage");
            click(0); frame();
            if(dut.game_state !== `ST_GENERATE) fail("stage confirm did not generate");
            guard=0;
            while(!dut.gen_done && guard<200000) begin cycles(1); guard=guard+1; end
            if(guard==200000) fail("real generation timed out");
            frame();
            if(dut.game_state !== `ST_PLAY || dut.active_game_cfg[3:0] !== (hard ? 4'd10 : 4'd5))
                fail("selected stage not captured into PLAY");
            oled_snapshot();
        end
    endtask
    task timeout;
        integer guard;
        begin
            guard=0;
            while(!dut.time_up && guard<4000) begin cycles(1); guard=guard+1; end
            if(guard==4000) fail("countdown failed to expire naturally");
            // time_up includes the terminal clock edge; process that edge.
            cycles(1);
            if(dut.game_state !== `ST_PLAY || dut.elapsed_seconds_bcd !== 0)
                fail("timeout bypassed VGA frame boundary or did not reach zero");
            frame();
            if(dut.game_state !== `ST_LOSE || dut.phys_en || dut.angle_rot_cmd !== 0)
                fail("timeout did not freeze gameplay into LOSE");
            if(dut.status_text[8*32+:8] !== "T" || dut.status_text[8*37+:8] !== "U" ||
               dut.status_text[8*38+:8] !== "P" || dut.status_text[8*25+:8] !== "0")
                fail("LOSE did not compose TIME UP / 00:00");
            // The real top must allow the LOSE panel through its RGB mask.
            // Probe a white T pixel and its red rim; raster details are
            // independently checked by tb_lose_render.
            if(!dut.render_enable || !dut.maze_ram_i.ren_r || !dut.render_i.lose_frame)
                fail("LOSE display/map reads remained masked");
            force dut.pixel_x=10'd156; force dut.pixel_y=10'd212;
            force dut.active_video=1; cycles(3);
            if({dut.vga_r,dut.vga_g,dut.vga_b} !== 12'hfff) fail("TIME UP glyph missing at top VGA pins");
            force dut.pixel_x=10'd140; force dut.pixel_y=10'd192; cycles(3);
            if({dut.vga_r,dut.vga_g,dut.vga_b} !== 12'hf22) fail("TIME UP red rim missing at top VGA pins");
            release dut.pixel_x; release dut.pixel_y; release dut.active_video;
            oled_snapshot();
            if(dut.text_active[8*32+:8] !== "T" || dut.text_active[8*37+:8] !== "U")
                fail("OLED active frame did not show TIME UP");
        end
    endtask
    integer stage;
    reg [11:0] frozen_angle;
    initial begin
        force dut.frame_tick=0; force dut.oled_frame_begin=0;
        cycles(20);
        for(stage=0;stage<2;stage=stage+1) begin
            start(stage); player_action(); frame();
            timeout(); frozen_angle=dut.angle;
            if(dut.status_text[8*6+:8] !== (stage ? "2" : "1")) fail("LOSE lost the active stage name");
            frame(); frame();
            if(dut.game_state !== `ST_LOSE || dut.angle !== frozen_angle) fail("LOSE hold ended early or angle moved");
            frame();
            if(dut.game_state !== `ST_MENU || dut.status_text[7:0] !== "S") fail("automatic menu return failed");
            if(dut.render_enable || dut.render_i.lose_frame) fail("TIME UP VGA panel remained after MENU");
            oled_snapshot();
            if(dut.text_active[7:0] !== "S") fail("TIME UP remained on OLED after menu return");
        end
        start(0); player_action(); timeout(); click(0);
        if(dut.game_state !== `ST_MENU || dut.elapsed_minutes_bcd !== 0 || dut.elapsed_seconds_bcd !== 0)
            fail("short CENTER reset from LOSE failed");
        oled_snapshot();
        start(1); player_action(); timeout(); btnC=1; cycles(96);
        if(!dut.full_reset || dut.game_state !== `ST_MENU || !dut.oled_reset)
            fail("full CENTER reset from LOSE missed controller/OLED");
        btnC=0; cycles(20); frame();
        if(dut.game_state !== `ST_MENU) fail("long release started an extra game");
        oled_snapshot();
        $display("PASS: Story 8.3 top natural EASY/HARD timeout, TIME UP VGA/OLED snapshots, automatic menu return and both resets");
        $finish;
    end
    initial begin #20000000; fail("timeout"); end
endmodule
