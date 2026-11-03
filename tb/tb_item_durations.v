`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Per-effect durations: every timed effect loads its own seconds and expires
// after exactly that many seconds, both on an immediate pickup and on a
// roulette commit. The time bonus has no duration.
module tb_item_durations;
    localparam HZ=4;
    reg clk=0,rst=1,init=0,done_i=0,done_d=0,commit=0;
    always #5 clk=~clk;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [3:0] n=5;
    reg [5:0] valid=6'b001111;
    reg signed [17:0] bx=0,by=0;
    reg [29:0] cols={10'd0,5'd5,5'd3,5'd5,5'd3}, rows={10'd0,5'd5,5'd5,5'd3,5'd3};
    reg [31:0] seed=32'h12345678;
    wire [3:0] effect_i,picked_i,effect_d,picked_d;
    wire [6:0] seconds_i,seconds_d;
    wire pulse_i,pulse_d,pending_d;
    // Distinct durations, 1..7 s, so a swapped table entry is caught.
    item_ctrl #(.CLK_HZ(HZ),.EFFECT_SECONDS(9),.RESPAWN_SECONDS(1),
        .LOW_GRAV_SECONDS(1),.INVINCIBLE_SECONDS(2),.REVERSE_GRAV_SECONDS(3),
        .HIGH_GRAV_SECONDS(4),.ZERO_GRAV_SECONDS(5),.INVERT_SECONDS(6),.FOG_SECONDS(7)) imm_i (
        .clk(clk),.rst(rst),.game_state(state),.phys_init(init),.phys_done(done_i),
        .roulette_busy(1'b0),.roulette_commit(1'b0),
        .n_cells(n),.ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(valid),.seed(seed),
        .active_effect(effect_i),.effect_seconds(seconds_i),.pickup_pulse(pulse_i),.pickup_effect(picked_i)
    );
    item_ctrl #(.CLK_HZ(HZ),.EFFECT_SECONDS(9),.RESPAWN_SECONDS(1),.DEFER_EFFECT(1),
        .LOW_GRAV_SECONDS(1),.INVINCIBLE_SECONDS(2),.REVERSE_GRAV_SECONDS(3),
        .HIGH_GRAV_SECONDS(4),.ZERO_GRAV_SECONDS(5),.INVERT_SECONDS(6),.FOG_SECONDS(7)) def_i (
        .clk(clk),.rst(rst),.game_state(state),.phys_init(init),.phys_done(done_d),
        .roulette_busy(1'b0),.roulette_commit(commit),
        .n_cells(n),.ball_x(bx),.ball_y(by),.box_cols(cols),.box_rows(rows),.box_valid(valid),.seed(seed),
        .active_effect(effect_d),.effect_seconds(seconds_d),.pickup_pulse(pulse_d),.pickup_effect(picked_d),
        .pending_valid(pending_d)
    );
    task fail; input [767:0] msg;
        // $finish, not $fatal: xsim carried on after $fatal in a task.
        begin $display("FAIL item durations: %0s",msg);$finish;end endtask
    task cycles; input integer c; begin repeat(c)@(negedge clk);end endtask
    task position; input integer c,r; begin bx=(c-n)*4096;by=(r-n)*4096;end endtask
    function integer expected; input [3:0] code;
        case(code)
            `ITEM_LOW_GRAV: expected=1;     `ITEM_INVINCIBLE: expected=2;
            `ITEM_REVERSE_GRAV: expected=3; `ITEM_HIGH_GRAV: expected=4;
            `ITEM_ZERO_GRAV: expected=5;    `ITEM_INVERT: expected=6;
            `ITEM_FOG: expected=7;          default: expected=0;
        endcase
    endfunction
    // After activation: still active one cycle before D seconds, gone at D.
    task check_run; input [3:0] code; input deferred;
        integer d;
        begin
            d=expected(code);
            if(code==`ITEM_TIME_BONUS)begin
                if((deferred ? effect_d : effect_i) !== `ITEM_NONE)fail("time bonus started a timed effect");
            end else begin
                if((deferred ? effect_d : effect_i) !== code ||
                   (deferred ? seconds_d : seconds_i) !== d)fail("effect did not load its own duration");
                cycles(d*HZ-1);
                if((deferred ? effect_d : effect_i) !== code ||
                   (deferred ? seconds_d : seconds_i) !== 1)fail("effect ended early");
                cycles(1);
                if((deferred ? effect_d : effect_i) !== `ITEM_NONE ||
                   (deferred ? seconds_d : seconds_i) !== 0)fail("effect outlived its duration");
            end
        end endtask
    // Respawn every box off the ball, then pick up one slot.
    task pickup; input integer slot; input deferred;
        begin
            position(1,1);cycles(HZ+2);
            if(deferred)begin done_d=1;cycles(1);done_d=0;end else begin done_i=1;cycles(1);done_i=0;end
            cycles((slot*3)%5+1);   // vary the roll
            position(cols[slot*5+:5],rows[slot*5+:5]);
            if(deferred)begin
                done_d=1;cycles(1);done_d=0;
                if(!pulse_d || !pending_d)fail("deferred pickup not held");
                cycles(2);commit=1;cycles(1);commit=0;
            end else begin
                done_i=1;cycles(1);done_i=0;
                if(!pulse_i)fail("immediate pickup missed");
            end
        end endtask
    integer i,pass;
    reg [7:0] seen;
    reg [3:0] code;
    initial begin
        cycles(2);rst=0;init=1;cycles(1);init=0;cycles(2);
        for(pass=0;pass<2;pass=pass+1)begin
            seen=0;
            for(i=0;i<200 && seen!=8'hff;i=i+1)begin
                pickup(i%4,pass);
                code = pass ? picked_d : picked_i;
                seen=seen|(8'b1<<code);
                check_run(code,pass);
            end
            if(seen!=8'hff)fail("not every effect was picked up");
        end
        $display("PASS: item durations per effect 1..7 s, immediate and roulette commit, exact expiry, time bonus untimed");
        $finish;
    end
    initial begin #50000000;fail("timeout");end
endmodule
