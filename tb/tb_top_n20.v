`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// The N = 20 test build (TEST_N_CELLS = 20) on the real top: the menu
// backdrop stays an N = 15 maze; the EASY menu entry starts an N = 20 game
// with start (39,39), goal (1,1), a 4:00 countdown, the ball and follow
// camera on the start tile, and a goal reachable through the 41 x 41 map in
// maze_ram at the 64-tile stride. Reaching the goal wins without touching
// the menu HIGH scores (the menu stage is not N = 20).
module tb_top_n20;
    reg clk=0, btnC=0;
    always #5 clk=~clk;
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(2), .WIN_HOLD_FRAMES(2),
        .TEST_N_CELLS(20)) dut (
        .clk(clk), .btnC(btnC), .btnU(1'b0), .btnD(1'b0), .btnL(1'b0), .btnR(1'b0),
        .sw(16'h0020), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail;
        input [767:0] msg;
        begin $display("FAIL N=20 top: %0s state=%0d n=%0d",msg,dut.game_state,dut.n_cells); $finish; end
    endtask
    task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
    task frame; begin force dut.frame_tick=1; cycles(1); force dut.frame_tick=0; cycles(8); end endtask
    task click_c; begin btnC=1; cycles(12); btnC=0; cycles(12); end endtask

    integer queue[0:`MAP_TILES-1];
    reg seen[0:`MAP_TILES-1];
    integer head,tail,a,b,k,row,col,dir,guard;
    initial begin
        force dut.frame_tick=0; cycles(16);
        guard=0;
        while(!dut.menu_bg_visible && guard<400000) begin cycles(1); guard=guard+1; end
        if(!dut.menu_bg_visible || dut.render_n_cells !== 15) fail("menu backdrop is not the N = 15 maze");

        click_c(); frame();
        if(dut.game_state !== `ST_GENERATE) fail("C did not start a game");
        guard=0;
        while(!dut.gen_done && guard<800000) begin cycles(1); guard=guard+1; end
        if(guard==800000) fail("N = 20 generation timeout");
        frame();
        if(dut.game_state !== `ST_PLAY || dut.n_cells !== 20 || dut.render_n_cells !== 20)
            fail("game is not N = 20");
        if(dut.start_col !== 39 || dut.start_row !== 39 || dut.goal_col !== 1 || dut.goal_row !== 1)
            fail("N = 20 start/goal tiles");
        if(dut.ball_x !== 19*4096 || dut.ball_y !== 19*4096 || dut.cam_x !== dut.ball_x || dut.cam_y !== dut.ball_y)
            fail("ball and follow camera not on the start tile");
        if(dut.elapsed_minutes_bcd !== 8'h04 || dut.elapsed_seconds_bcd !== 8'h00)
            fail("countdown did not load 4:00");

        // Tile BFS from the start through maze_ram (41 x 41 at stride 64).
        for(k=0;k<`MAP_TILES;k=k+1) seen[k]=0;
        a=39*`MAP_STRIDE+39; head=0; tail=1; queue[0]=a; seen[a]=1;
        if(dut.maze_ram_i.tile_mem[a] !== 0 || dut.maze_ram_i.tile_mem[`MAP_STRIDE+1] !== 0)
            fail("start or goal tile is a wall");
        while(head<tail) begin
            a=queue[head]; head=head+1; row=a/`MAP_STRIDE; col=a%`MAP_STRIDE;
            for(dir=0;dir<4;dir=dir+1) begin
                b=-1;
                case(dir)
                    0:if(row>0)b=a-`MAP_STRIDE;
                    1:if(col<40)b=a+1;
                    2:if(row<40)b=a+`MAP_STRIDE;
                    3:if(col>0)b=a-1;
                endcase
                if(b>=0 && !seen[b] && dut.maze_ram_i.tile_mem[b] === 0) begin
                    seen[b]=1; queue[tail]=b; tail=tail+1;
                end
            end
        end
        if(!seen[`MAP_STRIDE+1]) fail("goal not reachable from the N = 20 start");

        force dut.ball_i.ball_x=-19*4096; force dut.ball_i.ball_y=-19*4096;
        cycles(2); if(!dut.in_goal) fail("goal detector missed (1,1)");
        frame();
        if(dut.game_state !== `ST_WIN) fail("N = 20 goal did not win");
        if(dut.stage_high_scores_bcd !== 0) fail("test build changed a menu HIGH score");
        release dut.ball_i.ball_x; release dut.ball_i.ball_y;
        $display("PASS: N=20 top test build: N=15 backdrop, N=20 game, start (39,39), 4:00, follow camera, reachable goal, WIN, HIGH scores untouched");
        $finish;
    end
    initial begin #40000000; fail("timeout"); end
endmodule
