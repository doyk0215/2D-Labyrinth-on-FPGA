`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_instant_death_item;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,init=0,done=0,commit=0;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg signed [17:0] bx=0,by=0;
    wire [47:0] cols={6'd0,6'd0,6'd0,6'd0,6'd5,6'd3,6'd5,6'd3};
    wire [47:0] rows={6'd0,6'd0,6'd0,6'd0,6'd5,6'd5,6'd3,6'd3};
    wire [3:0] effect[0:1],picked[0:1];
    wire [6:0] seconds[0:1];wire [7:0] visible[0:1];
    wire death[0:1],blocked[0:1],pending[0:1],bonus[0:1];
    integer deaths[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin: paths
        item_ctrl #(.CLK_HZ(128),.EFFECT_SECONDS(20),.RESPAWN_SECONDS(1),.DEFER_EFFECT(g)) dut(
            .clk(clk),.rst(rst),.phys_init(init),.phys_done(done),.game_state(state),.n_cells(5'd10),
            .ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(8'h0f),.seed(32'h12345678),
            .roulette_busy(1'b0),.roulette_commit(commit),.box_visible(visible[g]),.active_effect(effect[g]),
            .effect_seconds(seconds[g]),.pickup_effect(picked[g]),.debuff_blocked(blocked[g]),
            .time_bonus_pulse(bonus[g]),.instant_death_pulse(death[g]),.pending_valid(pending[g]));
        always @(posedge clk)if(death[g])deaths[g]=deaths[g]+1;
    end endgenerate
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task fail;input [767:0] why;begin $display("FAIL instant death item: %0s",why);$fatal(1);end endtask
    task fresh;begin state=`ST_PLAY;bx=0;by=0;init=1;done=0;commit=0;cycles(1);init=0;cycles(2);end endtask
    task pick;input integer code;
        integer guard,slot;
        begin
            guard=0;slot=code<3 ? 0 : 2;
            while(((code<3 && paths[0].dut.buff_roll!=code) ||
                   (code==9 && paths[0].dut.debuff_roll!=5)) && guard<1000)begin cycles(1);guard=guard+1;end
            if(guard==1000)fail("random candidate not reached");
            bx=(cols[slot*6+:6]-10)*4096;by=(rows[slot*6+:6]-10)*4096;
            done=1;cycles(1);done=0;
        end
    endtask
    task apply_result;begin commit=1;cycles(1);commit=0;end endtask
    integer before_i,before_d,phase_i,phase_d;
    initial begin
        deaths[0]=0;deaths[1]=0;cycles(3);rst=0;fresh();
        pick(`ITEM_LOW_GRAV);apply_result();
        before_i=deaths[0];before_d=deaths[1];
        pick(`ITEM_INSTANT_DEATH);
        if(deaths[0]!=before_i+1 || deaths[1]!=before_d || !pending[1] || picked[0]!=9 || picked[1]!=9)
            fail("immediate/deferred death qualification");
        if(effect[0]!=`ITEM_LOW_GRAV || effect[1]!=`ITEM_LOW_GRAV)fail("instant death replaced active effect");
        phase_i=paths[0].dut.effect_subsecond;phase_d=paths[1].dut.effect_subsecond;
        state=`ST_PAUSED;commit=1;cycles(30);
        if(deaths[1]!=before_d || !pending[1] || paths[0].dut.effect_subsecond!=phase_i || paths[1].dut.effect_subsecond!=phase_d)
            fail("pause consumed/activated pending death");
        state=`ST_PLAY;cycles(1);commit=0;
        if(deaths[1]!=before_d+1 || pending[1] || effect[1]!=`ITEM_LOW_GRAV ||
           paths[1].dut.effect_subsecond!=phase_d+1 || bonus[0] || bonus[1])fail("commit refreshed effect or granted time");
        cycles(10);if(deaths[0]!=before_i+1 || deaths[1]!=before_d+1)fail("duplicate death pulse");
        fresh();pick(`ITEM_INVINCIBLE);apply_result();
        before_i=deaths[0];before_d=deaths[1];pick(`ITEM_INSTANT_DEATH);
        if(!blocked[0] || !blocked[1] || visible[0][2] || visible[1][2] || pending[1] ||
           deaths[0]!=before_i || deaths[1]!=before_d || effect[0]!=`ITEM_INVINCIBLE || effect[1]!=`ITEM_INVINCIBLE)
            fail("invincibility did not block/consume death box");
        fresh();pick(`ITEM_INSTANT_DEATH);before_d=deaths[1];state=`ST_MENU;commit=1;cycles(2);
        if(deaths[1]!=before_d || pending[1])fail("menu did not cancel deferred death");
        fresh();pick(`ITEM_INSTANT_DEATH);before_d=deaths[1];init=1;commit=1;cycles(1);init=0;commit=0;
        if(deaths[1]!=before_d || pending[1])fail("new maze did not cancel death");
        $display("PASS: instant death item ID9, full debuff pool, immediate/deferred exactly-once action, effect/phase preservation, invincibility and pause/reset cancellation");$finish;
    end
    initial begin #200000;fail("timeout");end
endmodule
