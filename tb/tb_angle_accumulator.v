`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_angle_accumulator;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg signed [1:0] rot_cmd = `ROT_NONE;
    wire [`ANGLE_W-1:0] angle;
    integer i;
    reg [`ANGLE_W-1:0] held_angle;

    always #5 clk = ~clk;

    angle_accumulator dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick),
        .rot_cmd(rot_cmd), .angle(angle)
    );

    task step_frame;
        begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
        end
    endtask

    task fail;
        input [255:0] message;
        begin
            $display("FAIL tb_angle_accumulator: %0s (angle=%0d)", message, angle);
            $finish;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        if (angle !== 12'd0) fail("reset angle");

        // No update between frame ticks, even while rotation is commanded.
        rot_cmd = `ROT_CW;
        repeat (20) @(negedge clk);
        if (angle !== 12'd0) fail("angle changed without frame_tick");

        // 1024 counts is 90 degrees on the nominal 60 Hz frame basis.
        for (i = 0; i < 60; i = i + 1) step_frame;
        if (angle !== 12'd1024) fail("clockwise one-second rate");

        // Releasing the command holds the exact angle over many frames.
        held_angle = angle;
        rot_cmd = `ROT_NONE;
        for (i = 0; i < 120; i = i + 1) step_frame;
        if (angle !== held_angle) fail("angle moved after release");

        // Reverse direction by 90 degrees, then wrap below zero.
        rot_cmd = `ROT_CCW;
        for (i = 0; i < 60; i = i + 1) step_frame;
        if (angle !== 12'd0) fail("counter-clockwise one-second rate");
        for (i = 0; i < 60; i = i + 1) step_frame;
        if (angle !== 12'd3072) fail("wrap below zero");

        // Clockwise 90 degrees from 270 degrees wraps back to zero.
        rot_cmd = `ROT_CW;
        for (i = 0; i < 60; i = i + 1) step_frame;
        if (angle !== 12'd0) fail("wrap above 360 degrees");

        // No-frame-tick intervals continue to hold after wrapping.
        rot_cmd = `ROT_NONE;
        held_angle = angle;
        repeat (25) @(negedge clk);
        if (angle !== held_angle) fail("angle changed between frame ticks");

        $display("PASS: angle_accumulator frame gating, 90 degree rate, release hold, direction, and wrap");
        $finish;
    end
endmodule
