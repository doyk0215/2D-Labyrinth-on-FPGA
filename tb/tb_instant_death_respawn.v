`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_instant_death_respawn;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,init=0,frame=0,request=0,pause_request=0,expired=0,goal=0;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [4:0] n=15;
    wire apply,discard_step;
    instant_death_respawn action_i(.clk(clk),.rst(rst),.phys_init(init),.frame_tick(frame),
        .request(request),.game_state(state),.pause_requested(pause_request),.time_up(expired),.in_goal(goal),.apply(apply),.discard_step(discard_step));
    wire signed [17:0] bx,by,cx,cy;
    wire signed [11:0] vx,vy;
    wire done,cam_done;
    wire [5:0] spawn=2*n-1;
    ball_physics ball_i(.clk(clk),.rst(rst),.frame_tick(frame),.phys_init(init),.instant_respawn(apply),
        .phys_en(state==`ST_PLAY),.spawn_col(spawn),.spawn_row(spawn),.goal_col(6'd1),.goal_row(6'd1),
        .n_cells(n),.sin_q(16'sd0),.cos_q(16'sd16384),.effect_code(`ITEM_NONE),.restitution_sel(2'd1),
        .maze_raddr(),.maze_rdata(1'b0),.ball_x(bx),.ball_y(by),.vel_x(vx),.vel_y(vy),.phys_done(done),.in_goal());
    camera camera_i(.clk(clk),.rst(rst),.phys_init(init || apply),.phys_done(done && !discard_step),
        .n_cells(n),.ball_x(bx),.ball_y(by),.cam_x(cx),.cam_y(cy),.cam_done(cam_done));
    integer applies=0;
    always @(posedge clk)if(apply)applies=applies+1;
    task cycles;input integer count;begin repeat(count)@(negedge clk);#1;end endtask
    task fail;input [767:0] why;
        begin $display("FAIL instant death respawn: %0s N=%0d state=%0d ball=%0d,%0d vel=%0d,%0d",why,n,state,bx,by,vx,vy);$fatal(1);end endtask
    task fresh;
        begin state=`ST_PLAY;init=1;frame=0;request=0;pause_request=0;expired=0;goal=0;cycles(2);init=0;cycles(4);end
    endtask
    task queue;begin request=1;cycles(1);request=0;end endtask
    task tick;begin frame=1;cycles(1);frame=0;end endtask
    task check_spawn;
        integer want;
        begin
            want=(n-1)*4096;
            if(bx!==want || by!==want || vx!==0 || vy!==0 || done)fail("spawn/velocity or stale completion");
            if(n>=11 && (cx!==want || cy!==want))fail("following camera did not snap to returned ball");
            if(n<11 && (cx!==0 || cy!==0))fail("fixed camera moved");
        end
    endtask
    integer size,phase,guard,before_count;
    initial begin
        cycles(3);rst=0;
        for(size=5;size<=20;size=size+5)for(phase=0;phase<5;phase=phase+1)begin
            n=size;fresh();
            ball_i.ball_x=0;ball_i.ball_y=0;ball_i.vel_x=300;ball_i.vel_y=-200;
            tick();guard=0;
            while(ball_i.state!=phase && guard<80)begin cycles(1);guard=guard+1;end
            if(guard==80)fail("collision phase not reached");
            before_count=applies;queue();
            if(apply)fail("mid-frame request applied immediately");
            tick();cycles(1);
            if(applies!=before_count+1)fail("missing frame-aligned action");
            cycles(6);check_spawn();cycles(30);check_spawn();
            if(applies!=before_count+1)fail("duplicate action or stale pipeline writeback");
        end
        fresh();before_count=applies;queue();pause_request=1;tick();
        if(apply)fail("pause-entry edge applied action");
        state=`ST_PAUSED;pause_request=0;cycles(20);
        if(!action_i.pending || applies!=before_count)fail("pause lost/applied pending action");
        state=`ST_PLAY;cycles(4);if(apply)fail("resume applied outside frame boundary");
        tick();cycles(7);check_spawn();if(applies!=before_count+1)fail("resume did not apply once");
        // Simulate game_ctrl's decision on the frame edge: terminal states
        // and regeneration must dominate the following respawn window.
        for(phase=0;phase<3;phase=phase+1)begin
            fresh();before_count=applies;queue();tick();
            state=phase==0 ? `ST_LOSE : phase==1 ? `ST_WIN : `ST_GENERATE;
            cycles(3);if(applies!=before_count || action_i.pending)fail("terminal/new-maze priority");
        end
        fresh();queue();expired=1;tick();
        if(!discard_step || apply)fail("deadline must block application while keeping stale-step mask");
        expired=0;#1;if(!discard_step || !apply)fail("registered stale-step mask depends on deadline guard");
        expired=1;cycles(3);if(apply)fail("deadline lost priority");
        fresh();queue();goal=1;tick();cycles(3);if(apply)fail("goal lost priority");
        fresh();queue();init=1;cycles(1);init=0;tick();cycles(3);if(action_i.pending)fail("phys_init did not cancel");
        fresh();queue();rst=1;cycles(1);rst=0;tick();cycles(3);if(action_i.pending)fail("reset did not cancel");
        $display("PASS: instant death respawn N=5/10/15/20, every collision phase, zero velocity, stale writeback, camera snap, pause/resume and terminal/reset priority");$finish;
    end
    initial begin #200000;fail("timeout");end
endmodule
