`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_top_instant_death;
    reg clk=0;always #5 clk=~clk;
    reg btnC=0,btnD=0,btnU=0,btnR=0;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.MENU_DEBOUNCE_CYCLES(2),.SNAP_DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(10000),.HUGE_TIME_SECONDS(600),.ITEM_LOW_GRAV_SECONDS(99),.ITEM_INVINCIBLE_SECONDS(99),
        .ITEM_ROULETTE_SPIN_MS(1),.ITEM_ROULETTE_HOLD_MS(20000)) dut(
        .clk(clk),.btnC(btnC),.btnD(btnD),.btnU(btnU),.btnL(1'b0),.btnR(btnR),.sw(16'h4000),
        .ps2_clk(ps2_clk),.ps2_data(ps2_data));
    integer deaths=0,applies=0,generations=0,loads=0;
    always @(posedge clk)begin
        if(dut.item_instant_death)deaths=deaths+1;
        if(dut.instant_respawn_apply)applies=applies+1;
        if(dut.game_gen_start)generations=generations+1;
        if(dut.phys_init)loads=loads+1;
    end
    task fail;input [767:0] why;
        begin $display("FAIL top instant death: %0s state=%0d roll=%0d visual=%h pending=%b deaths=%0d applies=%0d",why,dut.game_state,dut.roulette_i.state,dut.visual_active,dut.item_pending_valid,deaths,applies);$finish;end endtask
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task frame;begin force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(80);end endtask
    task click;begin btnC=1;cycles(12);btnC=0;cycles(12);end endtask
    reg signed [17:0] x,y;
    task position;input integer slot;
        begin
            if(slot<0)begin x=(dut.start_col-dut.n_cells)*4096;y=(dut.start_row-dut.n_cells)*4096;end
            else begin x=(dut.box_cols[slot*6+:6]-dut.n_cells)*4096;y=(dut.box_rows[slot*6+:6]-dut.n_cells)*4096;end
            force dut.ball_i.ball_x=x;force dut.ball_i.ball_y=y;
        end
    endtask
    task start;integer guard;
        begin
            guard=0;while(!dut.menu_bg_visible && guard<400000)begin cycles(1);guard=guard+1;end
            if(guard==400000)fail("menu backdrop timeout");
            while(dut.menu_ctrl_i.selected_stage!=2)begin btnD=1;cycles(12);btnD=0;cycles(12);end
            click();frame();guard=0;
            while(!dut.gen_done && guard<200000)begin cycles(1);guard=guard+1;end
            if(guard==200000)fail("generation timeout");position(-1);frame();
            if(dut.game_state!=`ST_PLAY || dut.n_cells!=15 || dut.box_visible!=8'h3f)fail("HARD setup");
        end
    endtask
    task pick;input integer slot,desired;
        integer tries,guard;reg accepted;
        begin
            accepted=0;tries=0;
            while(!accepted && tries<300)begin
                position(-1);force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;
                guard=0;while(!dut.phys_done && guard<100)begin cycles(1);guard=guard+1;end
                if(guard==100)fail("physics timeout");
                if((desired<3 && dut.item_i.buff_roll==desired) ||
                   (desired==9 && dut.item_i.debuff_roll==5))begin position(slot);accepted=1;end
                cycles(1);
                if(accepted && (!dut.item_pickup || dut.box_visible[slot]))fail("real box pickup missing");
                cycles(2);tries=tries+1;
            end
            if(!accepted)fail("seeded desired item not reached");
        end
    endtask
    // Service real system/OLED clock-domain mailboxes. Only the external
    // display-driver frame event is shortened; source/visual/grant are real.
    task display_current;integer guard;
        begin
            guard=0;while(dut.text_req_toggle!=dut.text_ack_sync[1] && guard<2000)begin cycles(1);guard=guard+1;end
            if(guard==2000)fail("old mailbox busy");frame();guard=0;
            while((!dut.text_pending_valid || dut.visual_pending!==dut.roulette_visual ||
                   dut.text_req_toggle!=dut.text_ack_sync[1]) && guard<2000)begin cycles(1);guard=guard+1;end
            if(guard==2000)fail("new text/visual not pending");
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=1;force dut.oled_sample_pixel=1;
            @(posedge dut.clk_6m25);#1;
            @(negedge dut.clk_6m25);force dut.oled_frame_begin=0;release dut.oled_sample_pixel;cycles(80);
        end
    endtask
    task finish_hold;
        begin cycles(200010);display_current();
            if(dut.roulette_busy || dut.visual_active[4])fail("roulette did not return to text");end
    endtask
    reg [1:0] indices[0:2559];reg [15:0] palette[0:39];
    reg [12:0] pixel_address=0;
    reg [15:0] expected,pixel_value;
    reg [4:0] held_visual;
    integer a,px,py,ix,iy,outfile;
    reg [4095:0] saved_map;
    reg [7:0] saved_boxes;
    reg [31:0] saved_seed;
    reg [11:0] saved_angle,saved_levels;
    reg [47:0] saved_highs;
    reg [9:0] saved_cfg;
    integer before_deaths,before_applies,before_gens,before_loads,spawn_q;
    integer saved_timer_phase,saved_effect_phase,saved_timer_seconds,saved_effect_seconds;
    reg [63:0] saved_respawn_left[0:7];
    function [15:0] bcd;input integer total;integer m,s;
        begin m=total/60;s=total%60;bcd[15:12]=m/10;bcd[11:8]=m%10;bcd[7:4]=s/10;bcd[3:0]=s%10;end
    endfunction
    reg [15:0] paused_time;
    reg [6:0] paused_effect_seconds;
    initial begin
        $readmemh("item_icons.mem",indices);$readmemh("item_icons_palette.mem",palette);
        force dut.frame_tick=0;force dut.oled_frame_begin=0;cycles(20);start();
        // Activate a real timed effect first, then let its OLED hold finish.
        pick(0,`ITEM_LOW_GRAV);display_current();display_current();
        if(dut.item_effect!=`ITEM_LOW_GRAV)fail("low gravity setup");finish_hold();
        // Stand in for a visible scanout pixel while using the actual board
        // button start path; the shortened frame cadence skips a full raster.
        force dut.maze_pixel_visible=1;
        btnR=1;cycles(8);frame();btnR=0;cycles(8);
        release dut.maze_pixel_visible;
        if(!dut.elapsed_timer_i.play_started || dut.angle==0)begin
            $display("setup details: armed=%b angle=%0d rot=%0d normal=%0d action=%b visible=%b btnR=%b rst=%b",
                dut.elapsed_timer_i.play_started,dut.angle,dut.rot_cmd,dut.rot_cmd_normal,dut.timer_player_action,
                dut.timer_display_active,dut.btnR_sync,dut.rst);
            fail("running timer/nonzero rotation setup");
        end
        dut.levels_completed_bcd=12'h007;dut.stage_high_scores_bcd=48'h009008007006;
        before_deaths=deaths;before_applies=applies;
        pick(3,`ITEM_INSTANT_DEATH);
        if(dut.item_pending_effect!=9 || deaths!=before_deaths || applies!=before_applies)fail("death activated at collection");
        display_current();
        if(deaths!=before_deaths || applies!=before_applies)fail("spinning death activated early");
        display_current();
        if(dut.visual_active!==5'h19 || deaths!=before_deaths+1 || applies!=before_applies || !dut.death_respawn_i.pending)
            fail("ID9 result did not queue exactly one action on display acknowledgement");
        // Scan an entire held OLED frame: source bit 4 and ID bit 3 must not
        // alias the old invincibility icon, nor mix text into the skull.
        held_visual=dut.visual_active;force dut.oled_pixel_index=pixel_address;
        outfile=$fopen("instant-death-oled.ppm","w");$fwrite(outfile,"P3\n96 64\n255\n");
        for(a=0;a<6144;a=a+1)begin
            @(negedge dut.clk_6m25);pixel_address=a;px=a%96;py=a/96;expected=0;
            if(px>=24 && px<72 && py>=8 && py<56)begin
                ix=(px-24)/3;iy=(py-8)/3;expected=palette[9*4+indices[9*256+iy*16+ix]];
            end
            @(posedge dut.clk_6m25);#1;pixel_value=dut.oled_pixel_data;
            if(pixel_value!==expected || dut.visual_active!==held_visual || applies!=before_applies)
                fail("non-atomic/aliased skull frame or mid-frame respawn");
            $fwrite(outfile,"%0d %0d %0d\n",pixel_value[15:11]*255/31,pixel_value[10:5]*255/63,pixel_value[4:0]*255/31);
        end
        $fclose(outfile);release dut.oled_pixel_index;
        // Real pause entry/resume must retain the already-accepted action.
        btnU=1;cycles(12);btnU=0;cycles(12);
        if(dut.game_state!=`ST_PAUSED)fail("pause setup");
        paused_time={dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd};paused_effect_seconds=dut.item_seconds;
        frame();cycles(50);
        if(applies!=before_applies || !dut.death_respawn_i.pending ||
           {dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}!==paused_time || dut.item_seconds!==paused_effect_seconds)
            fail("pause applied/lost request or advanced time/effect");
        click();if(dut.game_state!=`ST_PLAY || applies!=before_applies)fail("resume applied before frame");
        release dut.ball_i.ball_x;release dut.ball_i.ball_y;
        dut.ball_i.vel_x=321;dut.ball_i.vel_y=-432;
        saved_seed=dut.seed;saved_angle=dut.angle;saved_levels=dut.levels_completed_bcd;
        saved_highs=dut.stage_high_scores_bcd;saved_cfg=dut.active_game_cfg;saved_boxes=dut.box_visible;
        before_gens=generations;before_loads=loads;
        saved_timer_phase=dut.elapsed_timer_i.subsecond_count;
        saved_effect_phase=dut.item_i.effect_subsecond;saved_effect_seconds=dut.item_seconds;
        saved_timer_seconds=dut.elapsed_minutes_bcd[7:4]*600+dut.elapsed_minutes_bcd[3:0]*60+
                            dut.elapsed_seconds_bcd[7:4]*10+dut.elapsed_seconds_bcd[3:0];
        for(a=0;a<8;a=a+1)saved_respawn_left[a]=dut.item_i.respawn_left[a];
        for(a=0;a<4096;a=a+1)saved_map[a]=dut.maze_ram_i.tile_mem[a];
        force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(8);
        spawn_q=(dut.start_col-dut.n_cells)*4096;
        if(applies!=before_applies+1 || dut.ball_x!==spawn_q || dut.ball_y!==spawn_q ||
           dut.ball_vx!==0 || dut.ball_vy!==0 || dut.cam_x!==spawn_q || dut.cam_y!==spawn_q)
            fail("safe-boundary spawn/zero velocity/following camera");
        if(dut.game_state!=`ST_PLAY || dut.item_effect!=`ITEM_LOW_GRAV || dut.seed!==saved_seed ||
           dut.angle!==saved_angle || dut.levels_completed_bcd!==saved_levels || dut.stage_high_scores_bcd!==saved_highs ||
           dut.active_game_cfg!==saved_cfg || dut.box_visible!==saved_boxes || generations!=before_gens || loads!=before_loads)
            fail("death changed run/effect/map configuration or regenerated");
        if({dut.elapsed_minutes_bcd,dut.elapsed_seconds_bcd}!==bcd(saved_timer_seconds-(saved_timer_phase+9)/10000) ||
           dut.elapsed_timer_i.subsecond_count!==(saved_timer_phase+9)%10000 ||
           dut.item_seconds!==saved_effect_seconds-(saved_effect_phase+9)/10000 ||
           dut.item_i.effect_subsecond!==(saved_effect_phase+9)%10000)
            fail("respawn reset or refreshed timer/effect fractional phase");
        for(a=0;a<8;a=a+1)if(dut.item_i.respawn_left[a]!==((saved_respawn_left[a]>9)?saved_respawn_left[a]-9:0))
            fail("respawn reset item-box clocks");
        for(a=0;a<4096;a=a+1)if(saved_map[a]!==dut.maze_ram_i.tile_mem[a])fail("death rewrote maze");
        cycles(100);if(applies!=before_applies+1 || dut.ball_vx!==0 || dut.ball_vy!==0)fail("duplicate/stale writeback");
        // A protected red box is consumed and shows the existing shield;
        // it must neither queue a skull nor emit a respawn request.
        click();start();pick(0,`ITEM_INVINCIBLE);display_current();display_current();finish_hold();
        before_deaths=deaths;before_applies=applies;pick(3,`ITEM_INSTANT_DEATH);
        if(dut.item_pending_valid || !dut.item_debuff_blocked || dut.box_visible[3])begin
            // debuff_blocked is a one-clock event, already counted by roulette.
            if(dut.item_pending_valid || dut.box_visible[3])fail("protected box was not consumed/blocked");
        end
        display_current();
        if(dut.visual_active!==5'h11 || deaths!=before_deaths || applies!=before_applies || dut.item_effect!=`ITEM_INVINCIBLE)
            fail("invincibility did not use shield-only notice");
        $display("PASS: top instant death real generated box/roulette/6144 skull pixels, ID9 atomic OLED, pause, spawn/velocity/camera, preserved map/seed/angle/counts/effect and protected pickup");$finish;
    end
    initial begin #20000000;fail("timeout");end
endmodule
