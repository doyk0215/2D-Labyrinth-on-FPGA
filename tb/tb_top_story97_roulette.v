`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_top_story97_roulette;
    reg clk=0,btnC=0,btnD=0,btnR=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.MENU_DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(1000),.HARD_TIME_SECONDS(600),.ITEM_LOW_GRAV_SECONDS(8),.ITEM_HIGH_GRAV_SECONDS(8),.ITEM_INVINCIBLE_SECONDS(8),.ITEM_REVERSE_GRAV_SECONDS(8),.ITEM_ZERO_GRAV_SECONDS(8),.ITEM_INVERT_SECONDS(8),.ITEM_FOG_SECONDS(8),
        .ITEM_ROULETTE_SPIN_MS(64),.ITEM_ROULETTE_HOLD_MS(16),.ITEM_BLOCK_ICON_MS(16)) dut (
        .clk(clk),.btnC(btnC),.btnU(1'b0),.btnD(btnD),.btnL(1'b0),.btnR(btnR),
        .sw(16'h4000),.ps2_clk(ps2_clk),.ps2_data(ps2_data));
    task fail;input [767:0] msg;
        begin $display("FAIL Story 9.7 top: %0s state=%0d roll=%0d visual=%h pending=%b effect=%0d",msg,dut.game_state,dut.roulette_i.state,dut.visual_active,dut.item_pending_valid,dut.item_effect);$finish;end endtask
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task frame;begin @(negedge clk);#1;force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(80);end endtask
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
            if(guard==200000)fail("generation timeout");position(-1);frame();
            if(dut.game_state!==`ST_PLAY || dut.box_visible!==15)fail("new game");end endtask
    reg signed [17:0] x,y;
    task position;input integer slot;
        begin
            if(slot<0)begin x=(dut.start_col-dut.n_cells)*4096;y=(dut.start_row-dut.n_cells)*4096;end
            else begin x=(dut.box_cols[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;y=(dut.box_rows[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;end
            force dut.ball_i.ball_x=x;force dut.ball_i.ball_y=y;
        end endtask
    task pick;input integer slot,desired;integer tries,guard;reg accepted;
        begin tries=0;accepted=0;
            while(!accepted && tries<200)begin
                position(-1);force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;
                guard=0;while(!dut.phys_done && guard<100)begin cycles(1);guard=guard+1;end
                if(guard==100)fail("physics timeout");
                if(desired<0 || dut.item_i.buff_roll==desired)begin position(slot);accepted=1;end
                cycles(1);
                if(accepted && (!dut.item_pickup || dut.box_visible[slot]))fail("actual physics pickup");
                cycles(2);tries=tries+1;
            end
            if(!accepted)fail("seeded candidate not reached");end endtask
    task drain;integer guard;
        begin guard=0;
            while((!dut.text_pending_valid || dut.text_pending!==dut.status_text ||
                   dut.visual_pending!==dut.roulette_visual || dut.text_req_toggle!=dut.text_ack_sync[1]) && guard<3000)
                begin cycles(1);guard=guard+1;end
            if(guard==3000)fail("atomic text/visual mailbox did not settle");end endtask
    task oled_frame;
        begin
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=1;force dut.oled_sample_pixel=1;
            @(posedge dut.clk_6m25);#1;
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=0;release dut.oled_sample_pixel;cycles(80);
        end endtask
    reg [4:0] previous_visual=0;
    always @(posedge dut.clk_6m25)begin
        previous_visual=dut.visual_active;
        #1;if(!dut.oled_reset && !dut.oled_frame_begin && dut.visual_active!==previous_visual)
            fail("OLED visual changed inside a frame");
    end
    integer grants=0,completions=0;
    always @(posedge clk)begin if(dut.item_time_bonus)grants=grants+1;if(dut.phys_done)completions=completions+1;end
    reg [12:0] requested_pixel=0;
    reg [1:0] indices[0:2559];reg [15:0] palette[0:39];
    integer a,px,py,ix,iy,rom_address,saved_completions,saved_grants;
    reg [15:0] expected,saved_time;
    reg [4:0] frame_visual;
    initial begin
        $readmemh("item_icons.mem",indices);$readmemh("item_icons_palette.mem",palette);
        force dut.frame_tick=0;force dut.oled_frame_begin=0;cycles(20);start();
        pick(0,`ITEM_INVINCIBLE);
        if(!dut.item_pending_valid || dut.item_effect!==`ITEM_NONE || !dut.roulette_busy)fail("pickup not deferred");
        drain();
        // A counter boundary while the driver is still powering up is not
        // evidence of a visible frame and must not start the animation clock.
        if(dut.oled_sample_pixel)fail("power-up precondition missing");
        @(negedge dut.clk_6m25);force dut.oled_frame_begin=1;
        @(posedge dut.clk_6m25);#1;
        @(negedge dut.clk_6m25);force dut.oled_frame_begin=0;cycles(80);
        if(dut.roulette_i.shown || dut.item_effect!==`ITEM_NONE)fail("power-up frame counter started roulette");
        oled_frame();
        if(!dut.visual_active[4] || dut.item_effect!==`ITEM_NONE)fail("spin did not display before activation");
        frame_visual=dut.visual_active;
        // Even when the request changes to the selected icon, the frame being
        // scanned stays entirely on its original icon source with black margins.
        // Only a mouse click counts as the timer's first player action.
        force dut.maze_pixel_visible=1;force dut.timer_player_action=1;btnR=1;cycles(8);btnR=0;cycles(8);
        release dut.timer_player_action;release dut.maze_pixel_visible;
        saved_time={dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd};
        force dut.oled_pixel_index=requested_pixel;
        for(a=0;a<6144;a=a+1)begin
            @(negedge dut.clk_6m25);requested_pixel=a;px=a%96;py=a/96;expected=0;
            if(px>=24 && px<72 && py>=8 && py<56)begin
                ix=(px-24)/3;iy=(py-8)/3;rom_address=frame_visual[3:0]*256+iy*16+ix;
                expected=palette[frame_visual[3:0]*4+indices[rom_address]];
            end
            @(posedge dut.clk_6m25);#1;
            if(dut.oled_pixel_data!==expected || dut.visual_active!==frame_visual)fail("mixed/text pixel in roulette frame");
            if(dut.item_effect!==`ITEM_NONE)fail("effect started before selected result frame");
        end
        release dut.oled_pixel_index;
        if({dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}===saved_time || !dut.phys_en)
            fail("game countdown/physics stopped during spin");
        saved_completions=completions;position(1);frame();
        if(completions<=saved_completions || !dut.box_visible[1] || dut.item_pending_effect!==`ITEM_INVINCIBLE)begin
            $display("busy check: completions %0d -> %0d visible=%b selected=%0d phys_en=%b",saved_completions,completions,dut.box_visible,dut.item_pending_effect,dut.phys_en);
            fail("busy roulette stopped physics or consumed another box");
        end
        // Display the chosen result: activation occurs here, before HOLD ends.
        drain();oled_frame();
        if(dut.visual_active!==5'h11 || dut.item_effect!==`ITEM_INVINCIBLE || dut.item_pending_valid)
            fail("stopped-result frame did not activate effect");
        if(!dut.roulette_busy)fail("hold did not retain busy state");
        drain();oled_frame();
        if(dut.visual_active[4] || dut.roulette_busy || dut.text_active[8*48+:8]!=="B")fail("hold did not return to the PLAY text page");
        // Protected debuff gets an icon-only notice, without pending activation.
        pick(2,-1);if(dut.item_pending_valid || dut.item_pickup_effect!==`ITEM_NONE)fail("blocked debuff queued roulette");
        drain();oled_frame();if(dut.visual_active!==5'h11)fail("protection icon missing");
        drain();oled_frame();if(dut.visual_active[4] || dut.item_effect!==`ITEM_INVINCIBLE)fail("blocked icon disturbed protection");
        click();start();saved_grants=grants;pick(0,`ITEM_TIME_BONUS);
        if(grants!=saved_grants || {dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}!==16'h1000)fail("bonus fired at pickup");
        drain();oled_frame();drain();oled_frame();
        if(grants!=saved_grants+1 || {dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}!==16'h1010 || dut.item_effect!==`ITEM_NONE)
            fail("bonus not committed exactly once on selected icon");
        drain();oled_frame();
        click();start();pick(0,`ITEM_LOW_GRAV);force dut.game_ctrl_i.game_state=`ST_LOSE;cycles(4);
        if(dut.roulette_busy || dut.item_pending_valid || dut.item_effect!==`ITEM_NONE)fail("LOSE retained pending roll");
        drain();oled_frame();if(dut.visual_active[4] || dut.text_active[8*48+:8]!=="T")fail("LOSE did not restore TIME UP page");
        release dut.game_ctrl_i.game_state;btnC=1;cycles(96);
        if(!dut.full_reset || dut.item_pending_valid || dut.roulette_busy || dut.item_time_bonus)fail("full reset retained roulette");
        $display("PASS: Story 9.7 top atomic OLED frame, 6144 icon-only pixels, gameplay/busy gating, stopped-result activation, blocked icon, delayed bonus and LOSE/reset cancellation");
        $finish;
    end
    initial begin #40000000;fail("timeout");end
endmodule
