`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Real item/timer/controller handshake, with one manually completed physics step.
module tb_story95_items;
    localparam HZ=32;
    reg clk=0,rst=1,frame=0,generated=0,done=0,action=0,goal=0;
    always #5 clk=~clk;
    wire [`GAME_STATE_W-1:0] state;
    wire init,expired;
    wire [7:0] minutes,seconds;
    wire [3:0] visible,effect,picked;
    wire [6:0] effect_seconds;
    wire pulse,blocked,bonus;
    wire [1:0] index;
    reg signed [17:0] bx,by;
    wire [4*`COORD_W-1:0] cols={6'd5,6'd3,6'd5,6'd3}, rows={6'd5,6'd5,6'd3,6'd3};
    game_ctrl #(.START_IN_MENU(0),.WIN_HOLD_FRAMES(2),.LOSE_HOLD_FRAMES(2)) ctrl_i (
        .clk(clk),.rst(rst),.full_reset(1'b0),.frame_tick(frame),.start_game(1'b0),.game_cfg(10'h005),
        .regen_button(1'b0),.pause_button(1'b0),.pause_resume(1'b0),.pause_restart(1'b0),
        .gen_busy(1'b0),.gen_done(generated),.in_goal(goal),.time_up(expired),
        .game_state(state),.phys_init(init));
    item_ctrl #(.CLK_HZ(HZ),.EFFECT_SECONDS(4),.RESPAWN_SECONDS(1)) item_i (
        .clk(clk),.rst(rst),.game_state(state),.phys_init(init),.phys_done(done),.n_cells(5'd5),
        .roulette_busy(1'b0),.roulette_commit(1'b0),
        .ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(4'b1111),.seed(32'h12345678),
        .box_visible(visible),.active_effect(effect),.effect_seconds(effect_seconds),
        .pickup_pulse(pulse),.pickup_index(index),.pickup_effect(picked),.debuff_blocked(blocked),.time_bonus_pulse(bonus));
    game_timer #(.CLK_HZ(HZ),.EASY_SECONDS(1),.BONUS_SECONDS(10)) timer_i (
        .clk(clk),.rst(rst),.preserve_time(1'b0),.phys_init(init),.game_state(state),.n_cells(5'd5),
        .maze_pixel_visible(1'b1),.player_action(action),.time_bonus_pulse(bonus),
        .elapsed_minutes_bcd(minutes),.elapsed_seconds_bcd(seconds),.time_up(expired));
    integer bonuses=0,blocks=0;
    always @(posedge clk)if(bonus)bonuses=bonuses+1;
    always @(negedge clk)if(blocked)blocks=blocks+1;
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task fail;input [767:0] msg;
        begin $display("FAIL Story 9.5 items: %0s state=%0d effect=%0d seconds=%0d time=%02h:%02h",msg,state,effect,effect_seconds,minutes,seconds);$fatal(1);end endtask
    task position;input integer slot;
        begin if(slot<0)begin bx=-16384;by=-16384;end
            else begin bx=(cols[slot*`COORD_W+:`COORD_W]-5)*4096;by=(rows[slot*`COORD_W+:`COORD_W]-5)*4096;end end endtask
    task start;
        begin rst=1;frame=0;generated=0;done=0;goal=0;action=0;position(-1);cycles(2);rst=0;cycles(4);
            generated=1;frame=1;cycles(1);frame=0;generated=0;cycles(2);
            if(state!==`ST_PLAY || visible!==15 || seconds!==1)fail("new game initialization");end endtask
    task choose;input [3:0] code;integer guard;
        begin guard=0;while(item_i.buff_roll!=code && guard<1000)begin cycles(1);guard=guard+1;end
            force item_i.buff_roll=code[1:0];   // hold it: the roll changes every clock
            if(guard==1000)fail("seed never produced requested buff candidate");end endtask
    task pick;input integer slot;
        begin position(slot);done=1;cycles(1);done=0;
            if(!pulse || index!==slot || visible[slot])fail("pickup event/consumption");end endtask
    integer saved_sub,saved_seconds,before_bonus;
    initial begin
        start();choose(`ITEM_INVINCIBLE);pick(0);
        if(effect!==`ITEM_INVINCIBLE || effect_seconds!==4)fail("invincibility did not start");
        cycles(3);saved_sub=item_i.effect_subsecond;saved_seconds=effect_seconds;pick(2);
        if(!blocked || picked!==`ITEM_NONE || effect!==`ITEM_INVINCIBLE ||
           item_i.effect_subsecond!==saved_sub+1 || effect_seconds!==saved_seconds)fail("debuff changed/refreshed protection");
        cycles(1);if(blocked)fail("blocked notification wider than a clock");
        cycles(HZ+2);done=1;cycles(1);done=0;
        if(visible[2])fail("blocked debuff respawned under ball");
        position(-1);done=1;cycles(1);done=0;if(!visible[2])fail("blocked box did not respawn after departure");
        // Time bonus must not reset even the fractional phase of protection.
        choose(`ITEM_TIME_BONUS);saved_sub=item_i.effect_subsecond;saved_seconds=effect_seconds;before_bonus=bonuses;pick(1);
        if(bonuses!=before_bonus+1 || picked!==`ITEM_TIME_BONUS || effect!==`ITEM_INVINCIBLE ||
           item_i.effect_subsecond!==((saved_sub+1)%HZ) || effect_seconds!==(saved_seconds-(saved_sub==HZ-1)))
            fail("bonus replaced/refreshed the active effect");
        if({minutes,seconds}!==16'h0011)fail("instant bonus not added exactly once to unarmed timer");
        while(effect_seconds!=1 || item_i.effect_subsecond!=HZ-1)cycles(1);
        pick(3);
        if(!blocked || effect!==`ITEM_NONE || effect_seconds!==0)
            fail("last protection clock did not block or expiry deadline was refreshed");
        while(item_i.debuff_roll==5)cycles(1);
        pick(2);if(blocked || effect<`ITEM_REVERSE_GRAV || effect>`ITEM_FOG)fail("debuff still blocked after expiry");
        // An ordinary buff can replace invincibility.
        start();choose(`ITEM_INVINCIBLE);pick(0);choose(`ITEM_LOW_GRAV);pick(1);
        if(blocked || effect!==`ITEM_LOW_GRAV || effect_seconds!==4)fail("buff failed to replace protection");
        // Exact terminal edge + frame boundary: pickup must prevent LOSE.
        start();choose(`ITEM_TIME_BONUS);action=1;cycles(1);action=0;
        while(timer_i.subsecond_count!=HZ-1)cycles(1);
        if(!expired)fail("terminal edge precondition missing");
        position(0);done=1;frame=1;#1;
        if(!bonus || expired)fail("same-edge bonus did not suppress terminal deadline");
        cycles(1);done=0;frame=0;
        if(state!==`ST_PLAY || seconds!==8'h10 || effect!==`ITEM_NONE)fail("terminal pickup lost to LOSE or became timed");
        cycles(1);if(bonus)fail("bonus repeated after consumption");
        // A simultaneous goal is now a valid WIN with the extended time.
        start();choose(`ITEM_TIME_BONUS);action=1;cycles(1);action=0;
        while(timer_i.subsecond_count!=HZ-1)cycles(1);
        position(0);done=1;frame=1;goal=1;cycles(1);done=0;frame=0;goal=0;
        if(state!==`ST_WIN || seconds!==8'h10)fail("terminal bonus/goal priority");
        cycles(2);if(effect!==`ITEM_NONE || bonus || effect_seconds!==0)fail("terminal state retained effect/event");
        // WIN replay clears state and loads a fresh timer/boxes.
        frame=1;cycles(2);frame=0;cycles(4);generated=1;frame=1;cycles(1);frame=0;generated=0;cycles(2);
        if(state!==`ST_PLAY || seconds!==1 || visible!==15 || effect!==`ITEM_NONE)fail("replay retained bonus/effects");
        action=1;cycles(1);action=0;cycles(HZ);frame=1;cycles(1);frame=0;cycles(1);
        if(state!==`ST_LOSE || bonus || effect!==`ITEM_NONE)fail("ordinary timeout or LOSE clearing regressed");
        rst=1;position(0);done=1;#1;if(bonus)fail("reset emitted bonus");cycles(1);
        $display("PASS: Story 9.5 items invincibility, blocked consumption/respawn, instant nonreplacement bonus, exact-deadline controller priority and replay/reset clearing");
        $finish;
    end
    initial begin #200000;fail("timeout");end
endmodule
