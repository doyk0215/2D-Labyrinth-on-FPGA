`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Exercise the real menu, generator, RAM, physics goal detector and replay.
// Only frame timing and moving the ball directly to the goal are abbreviated.
module tb_top_story74_stage;
    reg clk=0, btnC=0, btnU=0, btnD=0, btnL=0;
    always #5 clk=~clk;
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(2),
        .WIN_HOLD_FRAMES(2)) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(1'b0),
        .sw(16'h0020), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail;
        input [767:0] msg;
        begin $display("FAIL Story 7.4: %0s state=%0d cfg=%h",msg,dut.game_state,dut.active_game_cfg); $fatal(1); end
    endtask
    task cycles;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task frame;
        begin force dut.frame_tick=1; cycles(1); force dut.frame_tick=0; cycles(8); end
    endtask
    task click;
        input integer id;
        begin
            case(id) 0:btnC=1; 1:btnU=1; 2:btnD=1; endcase
            cycles(12);
            case(id) 0:btnC=0; 1:btnU=0; 2:btnD=0; endcase
            cycles(12);
        end
    endtask
    task finish_generation;
        integer guard;
        begin
            guard=0;
            while(!dut.gen_done && guard<200000) begin cycles(1); guard=guard+1; end
            if(guard==200000) fail("N=15 generation timeout");
            frame();
            if(dut.game_state !== `ST_PLAY || dut.n_cells !== 15 || dut.active_game_cfg !== 8'h1F)
                fail("HUGE was not captured as active configuration");
            if(dut.start_col !== 29 || dut.start_row !== 29 || dut.goal_col !== 1 || dut.goal_row !== 1)
                fail("HUGE start/goal coordinates incorrect");
            if(dut.ball_x !== 18'sd57344 || dut.ball_y !== 18'sd57344 ||
               dut.ball_i.restitution_sel !== 1 || dut.cam_x !== dut.ball_x || dut.cam_y !== dut.ball_y)
                fail("ball did not spawn at bottom-right with snapped follow camera");
            if(dut.angle !== 12'd0)
                fail("fresh maze did not start at the canonical orientation");
        end
    endtask
    // Independent tile-level BFS through the generated map, starting at the
    // bottom-right cell. This does not assume a particular seed or DFS path.
    integer queue[0:1023];
    reg seen[0:1023];
    integer head,tail,a,b,k,row,col,dir;
    task check_reachable;
        begin
            for(k=0;k<1024;k=k+1) seen[k]=0;
            head=0; tail=1; queue[0]=29*32+29; seen[29*32+29]=1;
            if(dut.maze_ram_i.tile_mem[29*32+29] !== 0 || dut.maze_ram_i.tile_mem[33] !== 0)
                fail("start or goal tile is a wall");
            while(head<tail) begin
                a=queue[head]; head=head+1; row=a/32; col=a%32;
                for(dir=0;dir<4;dir=dir+1) begin
                    b=-1;
                    case(dir)
                        0:if(row>0)b=a-32;
                        1:if(col<30)b=a+1;
                        2:if(row<30)b=a+32;
                        3:if(col>0)b=a-1;
                    endcase
                    if(b>=0 && b<1024) begin
                        if(!seen[b] && dut.maze_ram_i.tile_mem[b] === 0) begin
                            seen[b]=1; queue[tail]=b; tail=tail+1;
                        end
                    end
                end
            end
            if(!seen[33]) fail("goal not reachable from generated HUGE start");
        end
    endtask
    integer i;
    initial begin
        force dut.frame_tick=0; cycles(16);
        // UP wraps to stage 3; DOWN traverses all three in forward order.
        click(1);
        if(dut.menu_ctrl_i.selected_stage !== 2 || dut.game_cfg !== 8'h1F ||
           dut.status_text[8*48+:8] !== ">") fail("UP did not select visible HUGE entry");
        click(2); if(dut.game_cfg !== 8'h05) fail("HUGE to EASY wrap failed");
        click(2); if(dut.game_cfg !== 8'h1A) fail("EASY to HARD failed");
        click(2); if(dut.game_cfg !== 8'h1F) fail("HARD to HUGE failed");
        click(0); frame();
        if(dut.game_state !== `ST_GENERATE || dut.active_game_cfg !== 8'h1F)
            fail("confirm did not latch HUGE");
        // Inputs after start must not change the active stage.
        click(1); click(2);
        finish_generation(); check_reachable();
        if(dut.status_text[8*6+:8] !== "3" || dut.status_text[8*10+:8] !== "G" ||
           dut.status_text[8*16+:8] !== "T" || dut.status_text[8*32+:8] !== "P")
            fail("HUGE PLAY name/time not formatted");
        for(i=0;i<2000;i=i+1) cycles(1);
        if(dut.text_mailbox !== dut.status_text || dut.text_pending !== dut.status_text)
            fail("HUGE status did not cross the real OLED mailbox");
        force dut.oled_frame_begin=1; cycles(80); release dut.oled_frame_begin;
        if(dut.text_active !== dut.status_text) fail("HUGE OLED frame did not capture complete text");
        // Rotate the first game, then verify WIN holds that orientation until
        // the automatic replay starts a freshly generated maze.
        btnL=1; cycles(6); frame(); btnL=0; cycles(6);
        if(dut.angle === 12'd0) fail("rotation setup failed before replay orientation check");
        // Use the actual physics goal detector, not a forced in_goal signal.
        force dut.ball_i.ball_x=-18'sd57344; force dut.ball_i.ball_y=-18'sd57344;
        cycles(2); if(!dut.in_goal) fail("N=15 goal detector missed goal centre");
        frame();
        if(dut.game_state !== `ST_WIN || dut.status_text[8*6+:8] !== "3" ||
           dut.status_text[8*32+:8] !== "Y") fail("HUGE WIN flow/status failed");
        if(dut.angle === 12'd0) fail("WIN did not retain the completed maze orientation");
        release dut.ball_i.ball_x; release dut.ball_i.ball_y;
        frame(); if(dut.game_state !== `ST_WIN) fail("WIN hold ended early");
        frame(); if(dut.game_state !== `ST_GENERATE) fail("WIN did not replay");
        finish_generation(); check_reachable();
        click(0);
        if(dut.game_state !== `ST_MENU || dut.game_cfg !== 8'h05) fail("CENTER did not restore EASY stage menu");
        $display("PASS: Story 7.4 HUGE menu, captured N=15, OLED, reachable goal, camera spawn, WIN and replay");
        $finish;
    end
    initial begin #20000000; fail("timeout"); end
endmodule
