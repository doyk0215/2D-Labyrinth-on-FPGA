`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Generated boxes and real physics completion; only ball position is placed.
module tb_top_time_pickup_hud;
    reg clk=0,btnC=0,btnD=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.MENU_DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(256),.HARD_TIME_SECONDS(59),.ITEM_LOW_GRAV_SECONDS(8),.ITEM_HIGH_GRAV_SECONDS(8),.ITEM_INVINCIBLE_SECONDS(8),.ITEM_REVERSE_GRAV_SECONDS(8),.ITEM_ZERO_GRAV_SECONDS(8),.ITEM_INVERT_SECONDS(8),.ITEM_FOG_SECONDS(8),
        .ITEM_RESPAWN_SECONDS(1),.ITEM_TIME_BONUS_SECONDS(10),.ITEM_ROULETTE_ENABLE(1'b1),.ITEM_ROULETTE_SPIN_MS(1),.ITEM_ROULETTE_HOLD_MS(1000)) dut (
        .clk(clk),.btnC(btnC),.btnU(1'b0),.btnD(btnD),.btnL(1'b0),.btnR(1'b0),
        .sw(16'h4000),.ps2_clk(ps2_clk),.ps2_data(ps2_data));
    integer grants=0,blocked_events=0;
    always @(posedge clk)if(dut.item_time_bonus)grants=grants+1;
    always @(posedge clk)if(dut.item_debuff_blocked)blocked_events=blocked_events+1;
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task fail;input [767:0] msg;
        begin $display("FAIL roulette time HUD: %0s effect=%0d seconds=%0d time=%02h:%02h",msg,dut.item_effect,dut.item_seconds,dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd);$finish;end endtask
    task frame;
        begin force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(80);end endtask
    task click;begin btnC=1;cycles(12);btnC=0;cycles(12);end endtask
    // MEDIUM (N = 10) has four boxes; EASY has none. Menu buttons are
    // ignored until the N = 20 backdrop maze is ready.
    task start;integer guard;
        begin guard=0;
            while(!dut.menu_bg_visible && guard<400000)begin cycles(1);guard=guard+1;end
            if(!dut.menu_bg_visible)fail("menu backdrop did not finish");
            if(dut.menu_ctrl_i.selected_stage!==2'd1)begin btnD=1;cycles(12);btnD=0;cycles(12);end
            if(dut.menu_ctrl_i.selected_stage!==2'd1)fail("could not select MEDIUM");
            click();frame();guard=0;
            while(!dut.gen_done && guard<200000)begin cycles(1);guard=guard+1;end
            if(guard==200000)fail("generation timeout");frame();
            if(dut.game_state!==`ST_PLAY || dut.box_visible!==15)fail("PLAY/placed boxes");end endtask
    reg signed [17:0] x,y;
    task position;input integer slot;
        begin
            if(slot<0)begin x=(dut.start_col-dut.n_cells)*4096;y=(dut.start_row-dut.n_cells)*4096;end
            else begin x=(dut.box_cols[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;y=(dut.box_rows[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;end
            force dut.ball_i.ball_x=x;force dut.ball_i.ball_y=y;
        end endtask
    task pick;
        input integer slot;input integer desired;
        integer tries,guard;reg accepted;
        begin
            tries=0;accepted=0;
            while(!accepted && tries<200)begin
                position(-1);force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;
                guard=0;while(!dut.phys_done && guard<100)begin cycles(1);guard=guard+1;end
                if(guard==100)fail("physics completion timeout");
                if(desired<0 || dut.item_i.buff_roll==desired)begin
                    position(slot);accepted=1;
                end
                cycles(1);
                if(accepted && (!dut.item_pickup || dut.box_visible[slot]))fail("real physics did not consume box");
                cycles(2);tries=tries+1;
            end
            if(!accepted)fail("seeded physics samples never selected requested buff");
        end endtask
    task display_current;
        integer guard;
        begin
            guard=0;
            while(dut.text_req_toggle!=dut.text_ack_sync[1] && guard<1000) begin cycles(1);guard=guard+1;end
            if(guard==1000)fail("previous mailbox request busy");
            frame();
            guard=0;
            while((!dut.text_pending_valid || dut.visual_pending!==dut.roulette_visual ||
                   dut.text_req_toggle!=dut.text_ack_sync[1]) && guard<1000) begin cycles(1);guard=guard+1;end
            if(guard==1000)fail("current icon not pending");
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=1;force dut.oled_sample_pixel=1;
            @(posedge dut.clk_6m25);#1;
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=0;release dut.oled_sample_pixel;
            cycles(80);
        end
    endtask
    initial begin
        force dut.frame_tick=0;force dut.oled_frame_begin=0;cycles(20);start();
        pick(0,`ITEM_TIME_BONUS);
        if(!dut.item_pending_valid || grants!=0 || dut.hud_i.notice_left!=0 || dut.hud_i.bonus_notice)
            fail("receipt appeared on pickup before roulette result");
        display_current();
        if(grants!=0 || dut.hud_i.notice_left!=0 || dut.hud_i.bonus_notice)
            fail("receipt appeared during spin");
        display_current();
        if(grants!=1 || {dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}!==16'h0109 || dut.hud_i.notice_left==0)
            fail("selected-result grant did not notify timer and HUD together");
        frame();
        if(!dut.hud_i.bonus_notice || dut.hud_i.item_status_line!=={"TIME +10s",{11{8'h20}}})
            fail("selected-result receipt not captured for VGA frame");
        force dut.pixel_x=10'd384;force dut.pixel_y=10'd38;force dut.active_video=1;cycles(3);
        if(!dut.hud_text || !dut.hud_bonus_line || {dut.vga_r,dut.vga_g,dut.vga_b}!==12'h4f4)
            fail("roulette receipt is not buff green at VGA pins");
        release dut.pixel_x;release dut.pixel_y;release dut.active_video;
        if(dut.item_effect!==`ITEM_NONE)fail("receipt created timed gameplay effect");
        cycles(600);frame();
        if(grants!=1 || dut.hud_i.bonus_notice || dut.hud_i.item_status_line!=={"ITEM NONE",{11{8'h20}}})
            fail("receipt did not expire or bonus applied twice");
        $display("PASS: roulette time pickup HUD stays hidden until selected result, same-edge timer grant, buff-green VGA text, exact-once bonus and ITEM NONE restore");
        $finish;
    end
    initial begin #10000000;fail("timeout");end
endmodule
