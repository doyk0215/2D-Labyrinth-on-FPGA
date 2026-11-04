`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// N = 20 through the CUSTOM menu stage on the real top (SW4..SW0 = 20, SW14
// fixed seed): the menu backdrop stays a centered N = 20 maze and the CUSTOM row
// shows N=20; DOWN x3 + C starts an N = 20 game with start (39,39), goal
// (1,1), a 4:00 countdown, the ball and follow camera on the start tile, and
// a goal reachable through the 41 x 41 map in maze_ram at the 64-tile
// stride. Moving the switches mid-game changes nothing, and reaching the
// goal wins without touching the menu HIGH scores (a CUSTOM game).
module tb_top_n20;
    reg clk=0, btnC=0, btnD=0, btnU=0, btnL=0, btnR=0;
    reg [15:0] sw=16'h4019;            // N = 25 first: invalid
    always #5 clk=~clk;
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(2), .WIN_HOLD_FRAMES(2),
        .MENU_ERROR_CYCLES(3000)) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR),
        .sw(sw), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail;
        input [767:0] msg;
        begin $display("FAIL N=20 top: %0s state=%0d n=%0d",msg,dut.game_state,dut.n_cells); $finish; end
    endtask
    task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
    task frame; begin force dut.frame_tick=1; cycles(1); force dut.frame_tick=0; cycles(8); end endtask
    task click_c; begin btnC=1; cycles(12); btnC=0; cycles(12); end endtask
    task click_d; begin btnD=1; cycles(12); btnD=0; cycles(12); end endtask
    task click_u; begin btnU=1; cycles(12); btnU=0; cycles(12); end endtask
    task click_l; begin btnL=1; cycles(12); btnL=0; cycles(12); end endtask
    task click_r; begin btnR=1; cycles(12); btnR=0; cycles(12); end endtask
    task wait_backdrop;
        integer guard;
        begin
            guard=0;
            while(!dut.menu_bg_visible && guard<400000) begin cycles(1); guard=guard+1; end
            if(!dut.menu_bg_visible) fail("menu backdrop timeout");
        end
    endtask

    function [127:0] menu_row;
        input integer r;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                menu_row[127 - 8 * i -: 8] = dut.menu_page_text[8 * (16 * r + i) +: 8];
        end
    endfunction

    // BTNC short press back to MENU, then wait for the backdrop (menu controls).
    task to_menu;
        integer guard;
        begin
            click_c(); frame();
            guard=0;
            while(!(dut.menu_active && dut.menu_bg_visible) && guard<400000) begin cycles(1); guard=guard+1; end
            if(!dut.menu_bg_visible) fail("BTNC did not return to the menu");
        end
    endtask
    // After a confirm: generate, check the game, put the ball on the goal, WIN.
    task play_to_win;
        input integer n;
        input custom;
        input [15:0] limit_bcd;
        integer guard;
        begin
            frame();
            guard=0;
            while(dut.game_state !== `ST_PLAY && guard<800) begin frame(); cycles(1000); guard=guard+1; end
            if(dut.game_state !== `ST_PLAY || dut.n_cells !== n || dut.active_game_cfg[9] !== custom)
                fail("confirm did not start the expected stage");
            if({dut.elapsed_minutes_bcd, dut.elapsed_seconds_bcd} !== limit_bcd) fail("stage time limit");
            if(dut.box_valid !== 6'b000000) fail("N <= 5 placed item boxes");
            if(dut.ball_i.restitution_sel !== 2'd0 || dut.hud_i.item_row_active !== 1'b0 ||
               dut.angle_i.rot_speed_sel !== 2'b10)
                fail("N <= 5 bounce, HUD item row or kept FAST rotation");
            force dut.ball_i.ball_x=-(n-1)*4096; force dut.ball_i.ball_y=-(n-1)*4096;
            cycles(2); if(!dut.in_goal) fail("goal detector missed (1,1)");
            frame();
            if(dut.game_state !== `ST_WIN) fail("goal did not win");
            release dut.ball_i.ball_x; release dut.ball_i.ball_y;
        end
    endtask

    integer queue[0:`MAP_TILES-1];
    reg seen[0:`MAP_TILES-1];
    integer head,tail,a,b,k,row,col,dir,guard;
    initial begin
        force dut.frame_tick=0; cycles(16);
        guard=0;
        while(!dut.menu_bg_visible && guard<400000) begin cycles(1); guard=guard+1; end
        if(!dut.menu_bg_visible || dut.render_n_cells !== 20) fail("menu backdrop is not the N = 20 maze");

        click_d(); click_d(); click_d();
        if(dut.menu_ctrl_i.selected_stage !== 2'd3) fail("DOWN x3 did not select CUSTOM");
        if(menu_row(3) !== ">CUSTOM N=25    ") fail("CUSTOM row does not show N=25");

        // Invalid size: the OLED error page, BTNR ignored, no game, then the menu.
        click_c(); frame();
        if(!dut.menu_error || dut.status_text[8*0 +: 8] !== "C" || dut.status_text[8*27 +: 8] !== "2")
            fail("invalid CUSTOM size did not show the error page");
        click_r();
        if(dut.instructions_active) fail("BTNR opened the instructions during the error page");
        guard=0;
        while(dut.menu_error && guard<10000) begin cycles(1); guard=guard+1; end
        if(dut.menu_error || dut.game_state !== `ST_MENU || dut.gen_busy ||
           dut.menu_ctrl_i.selected_stage !== 2'd3)
            fail("error page did not return to the unchanged menu");

        // Settings FAST, then back: the backdrop is regenerated, CUSTOM stays selected.
        click_l(); click_u();
        if(!dut.settings_page || dut.game_cfg[8:7] !== 2'b10) fail("settings did not select FAST");
        click_c(); wait_backdrop();
        sw[4:0]=5'd20; cycles(8);
        if(menu_row(3) !== ">CUSTOM N=20    ") fail("CUSTOM row does not show N=20");
        click_c(); frame();
        if(dut.game_state !== `ST_GENERATE) fail("C did not start a game");
        guard=0;
        while(!dut.gen_done && guard<800000) begin cycles(1); guard=guard+1; end
        if(guard==800000) fail("N = 20 generation timeout");
        frame();
        if(dut.game_state !== `ST_PLAY || dut.n_cells !== 20 || dut.render_n_cells !== 20 ||
           dut.active_game_cfg[9] !== 1'b1)
            fail("game is not a CUSTOM N = 20 game");
        if(dut.start_col !== 39 || dut.start_row !== 39 || dut.goal_col !== 1 || dut.goal_row !== 1)
            fail("N = 20 start/goal tiles");
        if(dut.ball_x !== 19*4096 || dut.ball_y !== 19*4096 || dut.cam_x !== dut.ball_x || dut.cam_y !== dut.ball_y)
            fail("ball and follow camera not on the start tile");
        if(dut.elapsed_minutes_bcd !== 8'h04 || dut.elapsed_seconds_bcd !== 8'h00)
            fail("countdown did not load 4:00");
        if(dut.box_valid !== 6'b111111) fail("N = 20 did not place six item boxes");
        if(dut.ball_i.restitution_sel !== 2'd1 || dut.angle_i.rot_speed_sel !== 2'b10 ||
           dut.hud_i.item_row_active !== 1'b1)
            fail("N = 20 bounce 1, FAST rotation or HUD item row did not reach the game");

        // The switches are read only when CUSTOM is confirmed.
        sw[4:0]=5'd7; cycles(8);
        if(dut.n_cells !== 20) fail("moving SW4..SW0 mid-game changed the maze size");

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
        if(dut.stage_high_scores_bcd !== 0) fail("a CUSTOM game changed a menu HIGH score");
        release dut.ball_i.ball_x; release dut.ball_i.ball_y;

        // The next level is generated at the same size, whatever the switches say.
        guard=0;
        while(dut.game_state !== `ST_PLAY && guard<800) begin
            frame(); cycles(1000); guard=guard+1;
        end
        if(dut.game_state !== `ST_PLAY || dut.n_cells !== 20) fail("next level is not N = 20");

        // EASY updates its HIGH score; CUSTOM N = 5 (the EASY size) and N = 2 do not.
        sw[4:0]=5'd5;
        to_menu(); click_c(); play_to_win(5, 1'b0, 16'h0100);
        if(dut.stage_high_scores_bcd !== 36'h000000001) fail("EASY win did not set EASY HIGH=1");
        to_menu(); click_d(); click_d(); click_d(); click_c(); play_to_win(5, 1'b1, 16'h0100);
        if(dut.stage_high_scores_bcd !== 36'h000000001) fail("CUSTOM N = 5 win changed a HIGH score");
        sw[4:0]=5'd2;
        to_menu(); click_d(); click_d(); click_d(); click_c(); play_to_win(2, 1'b1, 16'h0024);
        if(dut.stage_high_scores_bcd !== 36'h000000001) fail("CUSTOM N = 2 win changed a HIGH score");
        $display("PASS: N=20 top through CUSTOM: centered N=20 backdrop, CUSTOM N=20 row, N=20 game, start (39,39), 4:00, six boxes, switches ignored mid-game, reachable goal, WIN, HIGH scores untouched, next level N=20; invalid N=25 error page with BTNR ignored; FAST rotation, bounce and HUD item row reach the game; EASY win sets HIGH, CUSTOM N=5 and N=2 (0:24, no boxes) wins do not");
        $finish;
    end
    initial begin #60000000; fail("timeout"); end
endmodule
