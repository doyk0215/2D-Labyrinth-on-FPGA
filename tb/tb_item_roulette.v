`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Real item controller/roulette/timer with delayed, frame-aligned OLED feedback.
module tb_item_roulette;
    reg clk=0,rst=1,init=0,done=0;
    always #5 clk=~clk;
    reg [`GAME_STATE_W-1:0] game_state=`ST_PLAY;
    reg signed [17:0] bx=-16384,by=-16384;
    wire [4*`COORD_W-1:0] cols={6'd5,6'd3,6'd5,6'd3}, rows={6'd5,6'd5,6'd3,6'd3};
    wire [3:0] visible,effect,picked,pending;
    wire [6:0] seconds;
    wire pulse,blocked,bonus,pending_valid,busy,commit,returning;
    wire [1:0] index;
    wire [4:0] visual;
    reg display_frame=0;
    reg auto_display=1,near_action=0;
    reg [4:0] display_visual=0;
    integer frame_phase=0,commits=0,bonuses=0;
    wire [7:0] timer_minutes,timer_seconds;
    wire [7:0] near_minutes,near_seconds;
    wire near_deadline;
    item_ctrl #(.CLK_HZ(1000),.EFFECT_SECONDS(1),.RESPAWN_SECONDS(1),.DEFER_EFFECT(1)) item_i (
        .clk(clk),.rst(rst),.phys_init(init),.phys_done(done),.game_state(game_state),.n_cells(5'd5),
        .ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(4'b1111),.seed(32'h12345678),
        .roulette_busy(busy),.roulette_commit(commit),.box_visible(visible),.active_effect(effect),.effect_seconds(seconds),
        .pickup_pulse(pulse),.pickup_index(index),.pickup_effect(picked),.debuff_blocked(blocked),
        .time_bonus_pulse(bonus),.pending_valid(pending_valid),.pending_effect(pending));
    item_roulette #(.CLK_HZ(1000),.SPIN_MS(64),.HOLD_MS(16),.BLOCK_MS(16)) roulette_i (
        .clk(clk),.rst(rst),.phys_init(init),.game_state(game_state),.pickup_pulse(pulse),
        .pickup_index(index),.pickup_effect(picked),.debuff_blocked(blocked),.display_frame(display_frame),
        .display_visual(display_visual),.busy(busy),.visual(visual),.commit(commit),.returning(returning));
    game_timer #(.CLK_HZ(1000),.EASY_SECONDS(59)) timer_i (
        .clk(clk),.rst(rst),.preserve_time(1'b0),.phys_init(init),.game_state(game_state),.n_cells(5'd5),
        .maze_pixel_visible(1'b1),.player_action(1'b0),.time_bonus_pulse(bonus),
        .elapsed_minutes_bcd(timer_minutes),.elapsed_seconds_bcd(timer_seconds),.time_up());
    game_timer #(.CLK_HZ(1000),.EASY_SECONDS(1)) near_timer_i (
        .clk(clk),.rst(rst),.preserve_time(1'b0),.phys_init(init),.game_state(game_state),.n_cells(5'd5),
        .maze_pixel_visible(1'b1),.player_action(near_action),.time_bonus_pulse(bonus),
        .elapsed_minutes_bcd(near_minutes),.elapsed_seconds_bcd(near_seconds),.time_up(near_deadline));
    always @(negedge clk)begin
        frame_phase=frame_phase+1;
        display_frame=auto_display && (frame_phase%8)==0;
        if(display_frame)display_visual=visual;
    end
    always @(posedge clk)begin if(commit)commits=commits+1;if(bonus)bonuses=bonuses+1;end
    task fail;input [767:0] msg;
        begin $display("FAIL item roulette: %0s state=%0d pending=%b/%0d effect=%0d visual=%h",msg,roulette_i.state,pending_valid,pending,effect,visual);$fatal(1);end endtask
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task position;input integer slot;
        begin if(slot<0)begin bx=-16384;by=-16384;end
            else begin bx=(cols[slot*`COORD_W+:`COORD_W]-5)*4096;by=(rows[slot*`COORD_W+:`COORD_W]-5)*4096;end end endtask
    task fresh;
        begin game_state=`ST_PLAY;position(-1);init=1;done=0;cycles(1);init=0;cycles(2);
            if(pending_valid || busy || effect!==`ITEM_NONE || visible!==15)fail("new maze not clean");end endtask
    task pick_code;input integer code;integer guard,slot;
        begin slot=(code<3)?0:2;guard=0;
            while(((code<3 && item_i.buff_roll!=code) || (code>=3 && item_i.debuff_roll!=code-3)) && guard<2000)
                begin cycles(1);guard=guard+1;end
            if(guard==2000)fail("no seeded candidate");position(slot);done=1;cycles(1);done=0;
            if(!pulse || !pending_valid || pending!==code || effect!==`ITEM_NONE || visible[slot])fail("pickup did not defer exactly chosen effect");
            cycles(1);end endtask
    integer code,guard,previous_commits,previous_bonuses,first_interval,last_interval,seen_steps;
    reg [63:0] previous_interval;
    reg [3:0] previous_icon;
    task finish_roll;input integer selected;
        begin
            guard=0;previous_interval=0;seen_steps=0;previous_icon=visual[3:0];
            while(busy && guard<1000)begin
                if(roulette_i.state==roulette_i.SPIN && roulette_i.shown)begin
                    if((selected<3 && visual[3:0]>2) || (selected>=3 && visual[3:0]<3))fail("out-of-pool spin icon");
                    if(roulette_i.step_interval<previous_interval)fail("roulette sped up");
                    previous_interval=roulette_i.step_interval;
                    if(visual[3:0]!=previous_icon)seen_steps=seen_steps+1;
                    previous_icon=visual[3:0];
                end
                if(roulette_i.state==roulette_i.HOLD && visual[3:0]!==selected)fail("hold did not show selected result");
                // Roll over another box while busy: no consumption or event.
                position(1);done=1;cycles(1);done=0;
                if(pulse || !visible[1])fail("busy roulette allowed another pickup");
                if(pending_valid && effect!==`ITEM_NONE)fail("effect started before stopped result frame");
                guard=guard+1;
            end
            if(guard==1000 || seen_steps<3)fail("roulette failed to finish/cycle");
            if(pending_valid || commits!=previous_commits+1)fail("missing/duplicate delayed commit");
            if(selected==`ITEM_TIME_BONUS)begin
                if(effect!==`ITEM_NONE || bonuses!=previous_bonuses+1 || {timer_minutes,timer_seconds}!==16'h0109)
                    fail("delayed instant bonus changed effect or timer incorrectly");
            end else if(effect!==selected || seconds!==1 || bonuses!=previous_bonuses)fail("selected effect did not activate at stopped result");
        end endtask
    integer cancel_state,phase;
    initial begin
        cycles(2);rst=0;
        for(code=0;code<8;code=code+1)begin
            fresh();previous_commits=commits;previous_bonuses=bonuses;pick_code(code);finish_roll(code);
        end
        // Hold the result frame's acknowledgement until exactly the timer's
        // terminal edge; the delayed bonus must still win on that same edge.
        fresh();pick_code(`ITEM_TIME_BONUS);
        while(!roulette_i.shown)cycles(1);
        auto_display=0;display_frame=0;near_action=1;cycles(1);near_action=0;
        while(near_timer_i.subsecond_count!=999)cycles(1);
        if(!near_deadline || !pending_valid || roulette_i.state!=roulette_i.HOLD)fail("delayed terminal precondition");
        display_visual=visual;display_frame=1;#1;
        if(!commit || !bonus || near_deadline)fail("delayed bonus lost terminal priority");
        cycles(1);display_frame=0;
        if({near_minutes,near_seconds}!==16'h0010 || pending_valid)fail("delayed terminal bonus not applied once");
        auto_display=1;cycles(40);
        // Protected pickup shows only the protection icon and never commits.
        fresh();previous_commits=commits;previous_bonuses=bonuses;pick_code(`ITEM_INVINCIBLE);finish_roll(`ITEM_INVINCIBLE);
        previous_commits=commits;position(2);done=1;cycles(1);done=0;cycles(1);
        if(!busy || pending_valid || visual!==5'h11)fail("protected pickup did not enter icon-only notification");
        guard=0;while(busy && guard<200)begin
            if(visual[4] && visual[3:0]!==`ITEM_INVINCIBLE)fail("blocked pickup spun a debuff");
            cycles(1);guard=guard+1;
        end
        if(guard==200 || effect!==`ITEM_INVINCIBLE || commits!=previous_commits)fail("blocked notification altered protection");
        // Cancel at each roulette phase for every non-PLAY state.
        for(cancel_state=0;cancel_state<5;cancel_state=cancel_state+1)if(cancel_state!=`ST_PLAY)begin
            for(phase=1;phase<=4;phase=phase+1)if(phase!=3)begin
                fresh();previous_commits=commits;previous_bonuses=bonuses;pick_code(`ITEM_TIME_BONUS);
                guard=0;while(roulette_i.state!=phase && guard<1000)begin cycles(1);guard=guard+1;end
                if(guard==1000)fail("cancel phase not reached");
                previous_commits=commits;previous_bonuses=bonuses;
                game_state=cancel_state;#1;if(commit || bonus)fail("terminal transition leaked grant");cycles(2);
                if(busy || visual[4] || pending_valid || effect!==`ITEM_NONE || commits!=previous_commits || bonuses!=previous_bonuses)
                    fail("state change did not cancel pending roulette");
            end
        end
        fresh();pick_code(`ITEM_LOW_GRAV);rst=1;cycles(1);rst=0;
        if(busy || pending_valid || commit)fail("reset retained roulette");
        $display("PASS: item roulette all pools, slowing steps, selected hold, deferred effects/bonus, busy pickup gating, blocked icon and every-phase cancellation");
        $finish;
    end
    initial begin #1000000;fail("timeout");end
endmodule
