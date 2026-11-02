`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_item_ctrl;
    localparam HZ=4;
    reg clk=0,rst=1,init=0,done=0;
    always #5 clk=~clk;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [3:0] n=5,valid=15;
    reg signed [17:0] bx=0,by=0;
    reg [19:0] cols={5'd5,5'd3,5'd5,5'd3}, rows={5'd5,5'd5,5'd3,5'd3};
    reg [31:0] seed=32'h12345678;
    wire [3:0] visible,effect,picked;
    wire [6:0] seconds;
    wire pulse;
    wire blocked, bonus;
    wire [1:0] index;
    wire [3:0] stub_effect;
    item_ctrl #(.CLK_HZ(HZ),.EFFECT_SECONDS(2),.RESPAWN_SECONDS(3)) dut (
        .clk(clk),.rst(rst),.game_state(state),.phys_init(init),.phys_done(done),.roulette_busy(1'b0),.roulette_commit(1'b0),
        .n_cells(n),.ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(valid),.seed(seed),
        .box_visible(visible),.active_effect(effect),.effect_seconds(seconds),
        .pickup_pulse(pulse),.pickup_index(index),.pickup_effect(picked),
        .debuff_blocked(blocked),.time_bonus_pulse(bonus)
    );
    item_ctrl #(.CLK_HZ(HZ),.EFFECT_SECONDS(2),.RESPAWN_SECONDS(3),.STUB_LOW_ONLY(1)) stub_i (
        .clk(clk),.rst(rst),.game_state(state),.phys_init(init),.phys_done(done),.roulette_busy(1'b0),.roulette_commit(1'b0),
        .n_cells(n),.ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(valid),.seed(seed),
        .active_effect(stub_effect)
    );
    task fail;input [767:0] msg;
        begin $display("FAIL item_ctrl: %0s vis=%b effect=%0d sec=%0d",msg,visible,effect,seconds);$fatal(1);end endtask
    task cycles;input integer count;begin repeat(count)@(negedge clk);end endtask
    task position;input integer c,r;
        begin bx=(c-n)*4096;by=(r-n)*4096;end endtask
    task new_maze;
        begin init=1;done=0;position(1,1);cycles(1);init=0;
            if(visible !== valid || effect !== `ITEM_NONE || seconds !== 0)fail("phys_init did not reload boxes/clear effect");
            cycles(7);end endtask
    task choose_low;
        integer guard;
        begin guard=0;while(dut.buff_roll!=0 && guard<1000)begin cycles(1);guard=guard+1;end
            if(guard==1000)fail("no low-gravity candidate");end endtask
    task pickup;input integer slot;
        reg [3:0] previous_effect;
        begin
            previous_effect=effect;
            position(cols[slot*5+:5],rows[slot*5+:5]);done=1;cycles(1);done=0;
            if(!pulse || index !== slot || visible[slot] !== 0)fail("centre pickup failed");
            if(blocked)begin
                if(previous_effect!==`ITEM_INVINCIBLE || slot<2 || picked!==`ITEM_NONE)fail("invalid blocked pickup");
            end else begin
                if((slot<2 && picked>2) || (slot>=2 && (picked<3 || picked>7)))fail("effect outside its pool");
                if(picked!=`ITEM_TIME_BONUS && (effect!==picked || seconds!==2))fail("timed effect activation failed");
                if(picked==`ITEM_TIME_BONUS && effect==`ITEM_TIME_BONUS)fail("instant bonus became timed effect");
            end
            if(stub_effect !== `ITEM_LOW_GRAV)fail("stub option failed");
        end endtask
    task sample_no_pickup;
        begin done=1;cycles(1);done=0;
            if(pulse)fail("spurious pickup");end endtask
    integer i,slot;
    reg [7:0] seen=0;
    reg [3:0] first_roll;
    initial begin
        cycles(2);rst=0;new_maze();choose_low();
        // Coordinate boundaries are half-open and use the full signed sum.
        bx=(3-5)*4096-2049;by=(3-5)*4096;sample_no_pickup();
        bx=(3-5)*4096-2048;done=1;cycles(1);done=0;
        if(!pulse || index!==0)fail("inclusive left edge not picked up");
        cycles(HZ-1);if(seconds!==2)fail("effect duration lost its first partial second");
        cycles(1);if(seconds!==1)fail("effect did not count exactly one second");
        cycles(HZ);if(effect!==`ITEM_NONE || seconds!==0)fail("effect failed to expire");
        // Expired respawn stays hidden under the ball and never changes midframe.
        cycles(HZ*4);if(visible[0])fail("occupied box respawned");sample_no_pickup();
        if(visible[0])fail("occupied box appeared at physics boundary");
        position(1,1);cycles(3);if(visible[0])fail("visibility changed without phys_done");
        sample_no_pickup();if(!visible[0])fail("box did not respawn after departure");
        choose_low();pickup(0);cycles(2);pickup(2);
        if(visible[0] || visible[2] || !visible[1] || !visible[3])fail("per-box visibility/timers not independent");
        if(seconds!==2 || effect<3)fail("new pickup did not replace/restart old effect");
        // No underflow and no duplicate pickup while a hidden box is occupied.
        cycles(HZ*4);sample_no_pickup();if(visible[2] || seconds!==0)fail("hidden box repicked or timer wrapped");
        // Re-roll the same visible slots after respawn. Every cached candidate
        // belongs to its pool; all eight IDs occur across this deterministic run.
        new_maze();
        for(i=0;i<160;i=i+1)begin
            slot=i%4;position(1,1);cycles(HZ*3+3);sample_no_pickup();cycles((i%7)+1);
            pickup(slot);seen=seen|(8'b1<<picked);cycles(1);
            if(pulse)fail("pickup pulse wider than one system clock");
        end
        if(seen!==8'hff)fail("repeated fresh rolls did not cover every pool member");
        // Same seed and same input timing give the same first roll.
        new_maze();pickup(1);first_roll=picked;
        new_maze();pickup(1);if(picked!==first_roll)fail("same-seed timing not deterministic");
        // All non-PLAY states clear active/countdown state and cannot pick up.
        for(i=0;i<5;i=i+1)begin
            state=`ST_PLAY;new_maze();pickup(0);state=i;done=1;cycles(1);done=0;
            if(i!=`ST_PLAY && (effect!==`ITEM_NONE || seconds!==0 || pulse))fail("non-PLAY did not clear effect or blocked pickup");
        end
        state=`ST_PLAY;n=15;new_maze();
        // Absolute tile 35 aliases low five bits of tile 3; in_map must reject it.
        position(35,3);sample_no_pickup();
        cols[4:0]=29;rows[4:0]=29;new_maze();pickup(0);
        rst=1;cycles(1);rst=0;
        if(visible!==0 || effect!==`ITEM_NONE || seconds!==0 || pulse)fail("reset did not clear all item state");
        $display("PASS: item_ctrl pools, exact duration, replacement, per-box respawn/occupancy, signed boundaries, state clear and deterministic re-rolls");
        $finish;
    end
    initial begin #1000000;fail("timeout");end
endmodule
