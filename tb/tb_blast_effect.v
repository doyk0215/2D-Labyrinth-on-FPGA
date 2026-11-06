`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// blast_effect: six animation steps (flash, flash, ring 1, ring 2, embers,
// fading embers) of STEP_FRAMES frames each, centred on the blast tile.
// PAUSED freezes it, any other non-PLAY state or a new maze cancels it, and a
// second blast restarts it at the new tile. Fields only move on frame_tick.
module tb_blast_effect;
    localparam FRAMES=2;
    reg clk=0,rst=1,phys_init=0,frame_tick=0,start=0;
    always #5 clk=~clk;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [`COORD_W-1:0] ccol=6'd7,crow=6'd12;
    wire on,fill;
    wire [1:0] radius;
    wire [11:0] rgb;
    wire [`COORD_W-1:0] col,row;
    blast_effect #(.STEP_FRAMES(FRAMES)) dut(.clk(clk),.rst(rst),.phys_init(phys_init),
        .frame_tick(frame_tick),.game_state(state),.start(start),.centre_col(ccol),.centre_row(crow),
        .on(on),.col(col),.row(row),.fill(fill),.radius(radius),.rgb(rgb));
    task fail;input [511:0] msg;
        begin $display("FAIL blast effect: %0s on=%b step=%0d fill=%b radius=%0d rgb=%h col=%0d row=%0d",
            msg,on,dut.step,fill,radius,rgb,col,row);$finish;end endtask
    task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
    task frame;begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;@(negedge clk);end endtask
    task blast;input [`COORD_W-1:0] c,r;
        begin ccol=c;crow=r;@(negedge clk);start=1;@(negedge clk);start=0;@(negedge clk);end endtask
    task expect_step;input integer k;input exp_fill;input [1:0] exp_radius;input [11:0] exp_rgb;
        begin
            if(!on || dut.step!==k)fail("wrong step");
            if(fill!==exp_fill || radius!==exp_radius || rgb!==exp_rgb)fail("wrong fill/radius/colour for the step");
        end endtask
    integer i,k;
    initial begin
        cycles(3);rst=0;cycles(2);
        if(on)fail("running before any blast");
        for(i=0;i<5;i=i+1)frame();
        if(on)fail("frames alone started the effect");

        blast(6'd7,6'd12);
        if(col!==6'd7 || row!==6'd12)fail("centre tile not captured");
        expect_step(0,1,2'd2,12'hffe);
        // Each step lasts exactly FRAMES frame ticks.
        frame();expect_step(0,1,2'd2,12'hffe);
        frame();expect_step(1,1,2'd2,12'hfc4);
        frame();frame();expect_step(2,0,2'd1,12'hf82);
        frame();frame();expect_step(3,0,2'd2,12'hf62);
        frame();frame();expect_step(4,1,2'd2,12'ha30);
        frame();frame();expect_step(5,1,2'd2,12'h520);
        frame();if(!on)fail("ended one frame early");
        frame();if(on)fail("did not end after the last step");
        // The centre is not allowed to move once the blast is running.
        ccol=6'd30;cycles(3);if(col!==6'd7)fail("centre followed its input");

        // Pause freezes the animation and keeps it on screen.
        blast(6'd20,6'd5);frame();frame();expect_step(1,1,2'd2,12'hfc4);
        state=`ST_PAUSED;for(k=0;k<6;k=k+1)frame();
        expect_step(1,1,2'd2,12'hfc4);
        state=`ST_PLAY;frame();frame();expect_step(2,0,2'd1,12'hf82);
        // Leaving PLAY for the end screens cancels it.
        state=`ST_WIN;cycles(3);if(on)fail("WIN did not cancel the blast");
        state=`ST_PLAY;cycles(3);if(on)fail("blast came back after WIN");
        // A new maze (phys_init) and a reset cancel it too.
        blast(6'd3,6'd3);if(!on)fail("blast did not start");
        phys_init=1;@(negedge clk);phys_init=0;cycles(2);if(on)fail("phys_init did not cancel the blast");
        blast(6'd4,6'd4);rst=1;@(negedge clk);rst=0;cycles(2);if(on)fail("reset did not cancel the blast");
        // A second blast restarts the animation at its own tile.
        blast(6'd9,6'd9);for(i=0;i<5;i=i+1)frame();
        if(dut.step!==2)fail("second-blast precondition");
        blast(6'd15,6'd16);
        if(col!==6'd15 || row!==6'd16)fail("restart did not move the centre");
        expect_step(0,1,2'd2,12'hffe);
        // Fields are steady between frame ticks.
        for(i=0;i<20;i=i+1)begin cycles(1);if(dut.step!==0)fail("changed between frame ticks");end
        $display("PASS: blast effect six steps of %0d frames, centre captured, pause freeze, WIN/phys_init/reset cancel, restart at a new tile",FRAMES);
        $finish;
    end
    initial begin #2000000;fail("timeout");end
endmodule
