`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_game_timer;
    localparam CLK_HZ = 4;
    reg clk = 0, rst = 1, phys_init = 0, maze_pixel_visible = 0;
    reg [`GAME_STATE_W-1:0] game_state = `ST_GENERATE;
    reg [3:0] n_cells = 5;
    wire [7:0] minutes, seconds;
    wire time_up;
    always #5 clk = ~clk;
    game_timer #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst(rst), .maze_pixel_visible(maze_pixel_visible), .phys_init(phys_init), .game_state(game_state),
        .n_cells(n_cells), .elapsed_minutes_bcd(minutes),
        .elapsed_seconds_bcd(seconds), .time_up(time_up)
    );
    // CLK_HZ=1 exercises minimum counter width, all BCD borrows and cap.
    reg cap_init = 0;
    reg [3:0] cap_stage = 5;
    wire [7:0] cap_minutes, cap_seconds;
    game_timer #(.CLK_HZ(1), .EASY_SECONDS(6000), .HARD_SECONDS(-1),
                 .HUGE_SECONDS(600)) cap_i (
        .clk(clk), .rst(rst), .maze_pixel_visible(maze_pixel_visible), .phys_init(cap_init), .game_state(`ST_PLAY),
        .n_cells(cap_stage), .elapsed_minutes_bcd(cap_minutes),
        .elapsed_seconds_bcd(cap_seconds), .time_up()
    );
    task fail;
        input [511:0] message;
        begin $display("FAIL game_timer: %0s at %02h:%02h", message, minutes, seconds); $fatal(1); end
    endtask
    function [15:0] bcd;
        input integer total;
        integer m, s;
        begin m=total/60; s=total%60;
            bcd[15:12]=m/10; bcd[11:8]=m%10;
            bcd[7:4]=s/10; bcd[3:0]=s%10;
        end
    endfunction
    task cycles;
        input integer n;
        begin repeat(n) @(negedge clk); end
    endtask
    task visible_frame;
        begin
            @(negedge clk); maze_pixel_visible = 1'b1;
            @(negedge clk); maze_pixel_visible = 1'b0;
        end
    endtask
    task check;
        input integer total;
        begin if ({minutes,seconds} !== bcd(total)) fail("countdown differs from independent seconds model"); end
    endtask
    task load;
        input [3:0] stage;
        input integer total;
        begin n_cells=stage; phys_init=1; cycles(1); phys_init=0; check(total);
            if(time_up) fail("new nonzero limit already expired"); end
    endtask
    integer i, stage;
    initial begin
        cycles(2); rst=0;
        cycles(12); check(0);
        if(!time_up) fail("empty timer not marked expired");
        load(5,60);
        cycles(12); check(60); // generation never consumes time
        game_state=`ST_PLAY;
        cycles(CLK_HZ*3); check(60); // PLAY waits for the first visible maze pixel
        visible_frame();
        cycles(CLK_HZ-1); check(60);
        cycles(1); check(59);
        cycles(2); game_state=`ST_WIN;
        cycles(CLK_HZ*3); check(59);
        game_state=`ST_PLAY;
        cycles(CLK_HZ*3); check(59); // re-entry waits for a new visible maze pixel
        visible_frame();
        cycles(CLK_HZ-1); check(59); // discard partial second while paused
        cycles(1); check(58);
        game_state=`ST_LOSE; cycles(8); check(58);
        game_state=`ST_MENU; cycles(8); check(58);
        for(stage=5;stage<=15;stage=stage+5) begin
            game_state=`ST_PLAY;
            load(stage,stage*12);
            visible_frame();
            // Changing stage while playing cannot reload a running timer.
            n_cells=1;
            for(i=stage*12-1;i>=0;i=i-1) begin
                cycles(CLK_HZ); check(i);
            end
            if(!time_up) fail("zero did not expire");
            cycles(CLK_HZ*3); check(0); // saturation, no underflow
        end
        // Lookahead is asserted only for the actual final clock edge.
        load(5,60);
        visible_frame();
        cycles(59*CLK_HZ); check(1);
        cycles(CLK_HZ-2); if(time_up) fail("expiry asserted early");
        cycles(1); if(!time_up) fail("terminal second edge not exposed to controller");
        cycles(1); check(0);
        rst=1; cycles(1); rst=0; check(0);
        cap_stage=5; cap_init=1; cycles(1); cap_init=0;
        if({cap_minutes,cap_seconds} !== 16'h9959) fail("limit not capped at 99:59");
        visible_frame(); // arm only after active display video begins
        if({cap_minutes,cap_seconds} !== 16'h9959) fail("cap timer changed while arming");
        for(i=5998;i>=0;i=i-1) begin
            cycles(1);
            if({cap_minutes,cap_seconds} !== bcd(i)) begin
                $display("FAIL game_timer cap: expected %04h, got %02h%02h, started=%b, maze_pixel_visible=%b",
                         bcd(i), cap_minutes, cap_seconds, cap_i.play_started, cap_i.maze_pixel_visible);
                $fatal(1);
            end
        end
        cap_stage=10; cap_init=1; cycles(1); cap_init=0;
        if({cap_minutes,cap_seconds} !== 0) fail("negative limit not clamped to zero");
        cap_stage=15; cap_init=1; cycles(1); cap_init=0;
        if({cap_minutes,cap_seconds} !== 16'h1000) fail("parameterized HUGE limit not loaded");
        $display("PASS: game_timer stage countdown, BCD borrows, expiry edge, freeze, replay load, reset and saturation");
        $finish;
    end
    initial begin #1000000; fail("timeout"); end
endmodule
