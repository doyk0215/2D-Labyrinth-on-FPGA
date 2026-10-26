`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_snap_rotation;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg signed [1:0] rot_cmd = `ROT_NONE;
    reg snap_mode = 1'b0;
    reg rot_held = 1'b0;
    wire [11:0] angle;
    integer i;

    always #5 clk = ~clk;

    angle_accumulator dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick),
        .rot_cmd(rot_cmd), .snap_mode(snap_mode), .rot_held(rot_held),
        .angle(angle)
    );

    task fail;
        input [511:0] message;
        begin
            $display("FAIL tb_snap_rotation: %0s (angle=%0d)", message, angle);
            $finish;
        end
    endtask

    task step_frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
        end
    endtask

    task press_release;
        input signed [1:0] direction;
        begin
            @(negedge clk); rot_cmd = direction; rot_held = 1'b1;
            repeat (4) @(negedge clk);
            rot_cmd = `ROT_NONE; rot_held = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Switching on at a non-quadrant angle must not jump by itself.
        rot_cmd = `ROT_CW;
        for (i = 0; i < 3; i = i + 1) step_frame;
        if (angle !== 12'd51) fail("smooth setup");
        rot_cmd = `ROT_NONE;
        snap_mode = 1'b1;
        step_frame;
        if (angle !== 12'd51) fail("switch-on changed angle");

        // Holding a button across frames does not repeat. A release queues
        // the step, which is applied only at the next frame boundary.
        @(negedge clk); rot_cmd = `ROT_CW; rot_held = 1'b1;
        repeat (3) @(negedge clk);
        for (i = 0; i < 3; i = i + 1) step_frame;
        if (angle !== 12'd51) fail("button hold repeated or moved early");
        rot_cmd = `ROT_NONE; rot_held = 1'b0;
        repeat (2) @(negedge clk);
        if (angle !== 12'd51) fail("release moved angle between frames");
        step_frame;
        if (angle !== 12'd1024) fail("clockwise snap from fractional angle");

        press_release(`ROT_CW); step_frame;
        if (angle !== 12'd2048) fail("second clockwise snap");
        press_release(`ROT_CW); step_frame;
        if (angle !== 12'd3072) fail("third clockwise snap");
        press_release(`ROT_CW); step_frame;
        if (angle !== 12'd0) fail("clockwise quadrant wrap");
        press_release(`ROT_CCW); step_frame;
        if (angle !== 12'd3072) fail("counterclockwise wrap from zero");

        // Both buttons, or a change of direction during a press, cancel it.
        @(negedge clk); rot_held = 1'b1; rot_cmd = `ROT_NONE;
        repeat (3) @(negedge clk);
        rot_held = 1'b0;
        repeat (2) @(negedge clk);
        step_frame;
        if (angle !== 12'd3072) fail("both buttons caused a snap");
        @(negedge clk); rot_held = 1'b1; rot_cmd = `ROT_CW;
        repeat (3) @(negedge clk);
        rot_cmd = `ROT_NONE;
        repeat (2) @(negedge clk);
        rot_held = 1'b0;
        repeat (2) @(negedge clk);
        step_frame;
        if (angle !== 12'd3072) fail("ambiguous press caused a snap");

        // Re-enter smooth mode from the snapped angle without a jump.
        snap_mode = 1'b0;
        step_frame;
        if (angle !== 12'd3072) fail("switch-off changed angle");
        rot_cmd = `ROT_CW;
        for (i = 0; i < 60; i = i + 1) step_frame;
        if (angle !== 12'd0) fail("smooth mode did not resume at 90 deg/s");
        rot_cmd = `ROT_NONE;

        // From a fractional angle, CCW goes to the lower boundary.
        rot_cmd = `ROT_CW;
        step_frame;
        if (angle !== 12'd17) fail("fractional setup");
        rot_cmd = `ROT_NONE;
        snap_mode = 1'b1;
        press_release(`ROT_CCW); step_frame;
        if (angle !== 12'd0) fail("counterclockwise snap from fractional angle");

        // Reset and a sub-frame press/release must both be handled.
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        if (angle !== 12'd0) fail("reset angle");
        press_release(`ROT_CCW);
        if (angle !== 12'd0) fail("sub-frame press moved early");
        step_frame;
        if (angle !== 12'd3072) fail("sub-frame press was lost");

        // Multiple completed clicks before a frame must all contribute.
        press_release(`ROT_CW);
        press_release(`ROT_CW);
        if (angle !== 12'd3072) fail("two clicks moved between frames");
        step_frame;
        if (angle !== 12'd1024) fail("two clockwise clicks were not accumulated");
        press_release(`ROT_CCW);
        press_release(`ROT_CCW);
        step_frame;
        if (angle !== 12'd3072) fail("two counterclockwise clicks were lost");
        for (i = 0; i < 4; i = i + 1) press_release(`ROT_CW);
        step_frame;
        if (angle !== 12'd3072) fail("four clicks did not wrap a full turn");

        // Order matters at a fractional angle: CW then CCW reaches zero,
        // while CCW then CW reaches 90 degrees. A net direction count loses it.
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0; snap_mode = 1'b0;
        rot_cmd = `ROT_CW;
        step_frame;
        rot_cmd = `ROT_NONE; snap_mode = 1'b1;
        press_release(`ROT_CW);
        press_release(`ROT_CCW);
        step_frame;
        if (angle !== 12'd0) fail("CW then CCW lost fractional-angle ordering");
        snap_mode = 1'b0; rot_cmd = `ROT_CW;
        step_frame;
        rot_cmd = `ROT_NONE; snap_mode = 1'b1;
        press_release(`ROT_CCW);
        press_release(`ROT_CW);
        step_frame;
        if (angle !== 12'd1024) fail("CCW then CW lost fractional-angle ordering");

        // Consume one batch while another release arrives on the same edge.
        press_release(`ROT_CW);
        @(negedge clk); rot_cmd = `ROT_CW; rot_held = 1'b1;
        repeat (3) @(negedge clk);
        rot_cmd = `ROT_NONE; rot_held = 1'b0; frame_tick = 1'b1;
        @(negedge clk); frame_tick = 1'b0;
        if (angle !== 12'd2048) fail("frame did not consume older clicks");
        step_frame;
        if (angle !== 12'd3072) fail("release on frame boundary was lost");
        step_frame;
        if (angle !== 12'd3072) fail("pending clicks repeated after consumption");

        // Changing mode or resetting discards unconsumed clicks.
        press_release(`ROT_CW);
        snap_mode = 1'b0;
        repeat (2) @(negedge clk);
        snap_mode = 1'b1;
        step_frame;
        if (angle !== 12'd3072) fail("mode switch retained pending clicks");
        press_release(`ROT_CW);
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        step_frame;
        if (angle !== 12'd0) fail("reset retained pending clicks");

        $display("PASS: snap rotation press/release, ordered pending clicks, frame boundary, wrap, and mode switch");
        $finish;
    end
endmodule
