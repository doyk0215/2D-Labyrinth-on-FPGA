`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_angle_accumulator;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg signed [1:0] rot_cmd = `ROT_NONE;
    reg [1:0] rot_speed_sel = 2'b00;
    reg snap_mode = 1'b0;
    reg rot_held = 1'b0;
    wire [`ANGLE_W-1:0] angle;
    integer i;
    reg [`ANGLE_W-1:0] held_angle;

    always #5 clk = ~clk;

    angle_accumulator dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick),
        .rot_cmd(rot_cmd), .rot_speed_sel(rot_speed_sel),
        .snap_mode(snap_mode), .rot_held(rot_held),
        .angle(angle)
    );

    task step_frame;
        begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
        end
    endtask

    task reset_angle;
        begin
            @(negedge clk);
            rst = 1'b1;
            frame_tick = 1'b0;
            rot_cmd = `ROT_NONE;
            rot_held = 1'b0;
            snap_mode = 1'b0;
            repeat (2) @(negedge clk);
            rst = 1'b0;
            @(negedge clk);
        end
    endtask

    task check_rate;
        input [1:0] speed;
        input [11:0] expected_delta;
        integer k;
        begin
            reset_angle;
            rot_speed_sel = speed;
            rot_cmd = `ROT_CW;
            for (k = 0; k < 60; k = k + 1) step_frame;
            if (angle !== expected_delta)
                fail("clockwise rate did not match its 60-frame target");
            rot_cmd = `ROT_CCW;
            for (k = 0; k < 60; k = k + 1) step_frame;
            if (angle !== 12'd0)
                fail("counter-clockwise rate did not return to zero");
        end
    endtask

    task check_snap_rate;
        input [1:0] speed;
        begin
            reset_angle;
            rot_speed_sel = speed;
            snap_mode = 1'b1;
            @(negedge clk); rot_cmd = `ROT_CW; rot_held = 1'b1;
            repeat (3) @(negedge clk);
            rot_cmd = `ROT_NONE; rot_held = 1'b0;
            repeat (2) @(negedge clk);
            step_frame;
            if (angle !== 12'd1024)
                fail("snap rotation changed with the smooth-speed preset");
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

        check_rate(2'b01, 12'd512);
        check_rate(2'b00, 12'd1024);
        check_rate(2'b10, 12'd1536);
        check_rate(2'b11, 12'd2048);
        check_snap_rate(2'b00);
        check_snap_rate(2'b01);
        check_snap_rate(2'b10);
        check_snap_rate(2'b11);

        $display("PASS: angle_accumulator frame gating, four fractional rates, direction, wrap, and speed-independent snap");
        $finish;
    end
endmodule
