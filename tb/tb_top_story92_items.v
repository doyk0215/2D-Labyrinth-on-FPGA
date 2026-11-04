`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Real generator/placement, item engine, rendering, physics and OLED mailbox.
// Place only the ball at generated box centres to avoid steering-dependent
// coverage. Effects start from actual phys_done; item state is never forced.
module tb_top_story92_items;
    reg clk=0,btnC=0,btnD=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.MENU_DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(256),.HARD_TIME_SECONDS(99),.ITEM_LOW_GRAV_SECONDS(2),.ITEM_HIGH_GRAV_SECONDS(2),.ITEM_INVINCIBLE_SECONDS(2),.ITEM_REVERSE_GRAV_SECONDS(2),.ITEM_ZERO_GRAV_SECONDS(2),.ITEM_INVERT_SECONDS(2),.ITEM_FOG_SECONDS(2),
        .ITEM_RESPAWN_SECONDS(3),.ITEM_STUB_LOW_ONLY(1'b0),.ITEM_ROULETTE_ENABLE(1'b0),.WIN_HOLD_FRAMES(2)) dut (
        .clk(clk),.btnC(btnC),.btnU(1'b0),.btnD(btnD),.btnL(1'b0),.btnR(1'b0),
        .sw(16'h4000),.ps2_clk(ps2_clk),.ps2_data(ps2_data)
    );
    task fail;input [767:0] msg;
        begin $display("FAIL Story 9.2 top: %0s state=%0d vis=%b effect=%0d sec=%0d",msg,dut.game_state,dut.box_visible,dut.item_effect,dut.item_seconds);$finish;end endtask
    task cycles;input integer count;begin repeat(count)@(negedge clk);end endtask
    task frame;begin force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(80);end endtask
    task click;begin btnC=1;cycles(12);btnC=0;cycles(12);end endtask
    // MEDIUM (N = 10) has four boxes; EASY has none. Menu buttons are
    // ignored until the N = 20 backdrop maze is ready.
    task start;
        integer guard;
        begin guard=0;
            while(!dut.menu_bg_visible && guard<400000)begin cycles(1);guard=guard+1;end
            if(!dut.menu_bg_visible)fail("menu backdrop did not finish");
            if(dut.menu_ctrl_i.selected_stage !== 2'd1)begin btnD=1;cycles(12);btnD=0;cycles(12);end
            if(dut.menu_ctrl_i.selected_stage !== 2'd1)fail("could not select MEDIUM");
            click();frame();guard=0;
            while(!dut.gen_done && guard<200000)begin cycles(1);guard=guard+1;end
            if(guard==200000)fail("generator timeout");frame();
            if(dut.game_state !== `ST_PLAY || dut.box_visible !== 6'b001111)fail("new game failed to initialize placed boxes");end
    endtask
    reg signed [17:0] forced_x,forced_y;
    task ball_at;
        input integer col,row;
        begin forced_x=(col-dut.n_cells)*4096;forced_y=(row-dut.n_cells)*4096;
            force dut.ball_i.ball_x=forced_x;force dut.ball_i.ball_y=forced_y;cycles(2);end
    endtask
    reg signed [26:0] probe_x,probe_y;
    task probe_buff;
        input [11:0] expected;
        begin probe_x=(dut.box_cols[`COORD_W-1:0]*16+2)*16384;probe_y=(dut.box_rows[`COORD_W-1:0]*16+2)*16384;
            force dut.render_i.walk_x_q=probe_x;force dut.render_i.walk_y_q=probe_y;
            force dut.ball_on=0;force dut.active_video=1;cycles(4);
            if({dut.vga_r,dut.vga_g,dut.vga_b} !== expected)fail("visible/hidden box VGA pixel incorrect");
            release dut.render_i.walk_x_q;release dut.render_i.walk_y_q;
            release dut.ball_on;release dut.active_video;end
    endtask
    integer c,r;
    initial begin
        force dut.frame_tick=0;force dut.oled_frame_begin=0;cycles(20);start();
        probe_buff(12'h04f);
        c=dut.box_cols[`COORD_W-1:0];r=dut.box_rows[`COORD_W-1:0];ball_at(c,r);frame();
        if(dut.box_visible[0] || dut.item_pickup_effect > `ITEM_TIME_BONUS ||
           (dut.item_pickup_effect != `ITEM_TIME_BONUS && dut.item_seconds==0))
            fail("actual physics completion did not pick up generated buff");
        if(dut.ball_i.effect_code !== dut.item_effect)fail("effect did not reach physics");
        probe_buff(12'h346);
        // The item status is on the VGA HUD; the OLED page stays on PLAY.
        if(dut.status_text[8*48+:8] !== "B")fail("item pickup changed the OLED status page");
        cycles(800);frame();
        if(dut.box_visible[0] || dut.item_effect !== `ITEM_NONE || dut.item_seconds!==0)
            fail("effect expiry or occupied respawn failed");
        ball_at(dut.start_col,dut.start_row);frame();
        if(!dut.box_visible[0])fail("box did not reappear on departure");probe_buff(12'h04f);
        ball_at(c,r);frame();if(dut.item_pickup_effect > `ITEM_TIME_BONUS)fail("respawned buff box did not roll from its pool");
        release dut.ball_i.ball_x;release dut.ball_i.ball_y;
        click();if(dut.game_state !== `ST_MENU || dut.item_effect!==`ITEM_NONE || dut.box_visible!==0)
            fail("short reset retained item/respawn state");
        start();ball_at(dut.box_cols[2*`COORD_W +: `COORD_W],dut.box_rows[2*`COORD_W +: `COORD_W]);frame();
        if(dut.box_visible[2] || dut.item_effect < `ITEM_REVERSE_GRAV || dut.item_effect > `ITEM_FOG)fail("debuff slot did not roll from its own pool");
        force dut.game_ctrl_i.game_state=`ST_WIN;cycles(2);
        if(dut.item_effect!==`ITEM_NONE || dut.item_seconds!==0)fail("WIN did not clear active item");
        release dut.game_ctrl_i.game_state;click();release dut.ball_i.ball_x;release dut.ball_i.ball_y;
        start();ball_at(dut.box_cols[`COORD_W-1:0],dut.box_rows[`COORD_W-1:0]);frame();
        force dut.game_ctrl_i.game_state=`ST_LOSE;cycles(2);
        if(dut.item_effect!==`ITEM_NONE || dut.item_seconds!==0)fail("LOSE did not clear active item");
        release dut.game_ctrl_i.game_state;btnC=1;cycles(96);
        if(!dut.full_reset || dut.item_effect!==`ITEM_NONE || dut.box_visible!==0)fail("full reset retained item state");
        btnC=0;cycles(20);release dut.ball_i.ball_x;release dut.ball_i.ball_y;
        if(dut.game_state !== `ST_MENU)fail("long release started a game");
        $display("PASS: Story 9.2 MEDIUM generated-box pickup, VGA hiding/respawn, full-pool effect-bus wiring, OLED page unchanged and terminal/reset clearing");
        $finish;
    end
    initial begin #40000000;fail("timeout");end
endmodule
