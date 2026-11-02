`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_switch_mapping;
    reg clk=0,btnR=0;
    reg [15:0] sw=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.SNAP_DEBOUNCE_CYCLES(2)) dut (
        .clk(clk),.btnC(1'b0),.btnU(1'b0),.btnD(1'b0),.btnL(1'b0),.btnR(btnR),
        .sw(sw),.ps2_clk(ps2_clk),.ps2_data(ps2_data)
    );
    task fail; input [511:0] msg;
        begin $display("FAIL switch mapping: %0s",msg); $fatal(1); end endtask
    task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
    task frame; begin force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(5);end endtask
    reg [31:0] first_seed;
    initial begin
        force dut.frame_tick=0; cycles(12);
        if(dut.snap_mode) fail("default switches selected snap");
        first_seed=dut.seed;cycles(8);if(dut.seed===first_seed) fail("SW5 low did not select running seed");
        sw[5]=1;cycles(8);
        if(dut.snap_mode || dut.seed !== 32'hc0ffee01) fail("SW5 did not select fixed seed independently of snap");
        sw[0]=1;cycles(8);
        if(!dut.snap_mode || dut.seed !== 32'hc0ffee01) fail("SW0 changed fixed seed or did not enable snap");
        sw[5]=0;cycles(8);first_seed=dut.seed;cycles(8);
        if(!dut.snap_mode || dut.seed===first_seed) fail("SW5 altered snap or failed to restore running seed");
        force dut.game_ctrl_i.game_state=`ST_PLAY;
        btnR=1;cycles(12);frame();
        if(dut.angle !== 0) fail("snap moved before release");
        btnR=0;cycles(12);frame();
        if(dut.angle !== 1024) fail("SW0 snap did not advance to 90 degrees");
        sw[0]=0;sw[5]=1;cycles(8);btnR=1;cycles(8);frame();btnR=0;cycles(8);
        if(dut.angle !== 1041 || dut.seed !== 32'hc0ffee01) fail("SW5 fixed seed did not preserve independent smooth rotation");
        release dut.game_ctrl_i.game_state;
        $display("PASS: switch mapping SW0 snap, SW5 fixed seed, independent four combinations and rotation");
        $finish;
    end
    initial begin #100000;fail("timeout");end
endmodule
