`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 9.4 invert controls on the real top: board buttons and PS/2 buttons,
// snap and smooth rotation, with item_ctrl's effect forced to INVERT and back.
module tb_top_story94_invert;
    reg clk = 0, btnL = 0, btnR = 0;
    reg [15:0] sw = 0;
    always #5 clk = ~clk;
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .SNAP_DEBOUNCE_CYCLES(2)) dut (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnD(1'b0), .btnL(btnL), .btnR(btnR),
        .sw(sw), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    task fail; input [511:0] msg;
        begin
            $display("FAIL Story 9.4 invert: %0s (angle=%0d effect=%0d snap=%b L=%b R=%b cmd=%0d)",
                     msg, dut.angle, dut.item_effect, dut.snap_mode, dut.snap_left, dut.snap_right,
                     dut.angle_rot_cmd);
            $finish;
        end
    endtask
    task cycles; input integer n; begin repeat (n) @(negedge clk); end endtask
    task frame; begin force dut.frame_tick = 1; cycles(1); force dut.frame_tick = 0; cycles(5); end endtask
    task effect; input [3:0] code; begin force dut.item_i.active_effect = code; cycles(2); end endtask

    // which: 0 board left, 1 board right, 2 mouse left, 3 mouse right.
    // Forces use constants: "force x = level" would keep x tied to the
    // task's shared argument, so a later call would also move this button.
    task press; input integer which; input level;
        begin
            case (which)
                0: btnL = level;
                1: btnR = level;
                2: if (level) force dut.mouse_left = 1'b1; else force dut.mouse_left = 1'b0;
                default: if (level) force dut.mouse_right = 1'b1; else force dut.mouse_right = 1'b0;
            endcase
            cycles(8);
        end
    endtask
    // A complete snap click, then the frame that applies it.
    task snap_click; input integer which; input [11:0] expected; input [511:0] msg;
        begin
            press(which, 1); frame(); press(which, 0); frame();
            if (dut.angle !== expected) fail(msg);
        end
    endtask
    // One smooth frame held; sign: +1 clockwise, -1 counter-clockwise.
    reg [11:0] before;
    reg signed [12:0] delta;
    task smooth_frame; input integer which; input integer sign; input [511:0] msg;
        begin
            before = dut.angle;
            press(which, 1); frame(); press(which, 0);
            delta = $signed({1'b0, dut.angle}) - $signed({1'b0, before});
            if (delta > 2048) delta = delta - 4096;
            if (delta < -2048) delta = delta + 4096;
            if ((sign > 0 && (delta < 1 || delta > 64)) || (sign < 0 && (delta > -1 || delta < -64)))
                fail(msg);
        end
    endtask

    initial begin
        force dut.frame_tick = 0;
        force dut.mouse_left = 0; force dut.mouse_right = 0;
        cycles(12);
        force dut.game_ctrl_i.game_state = `ST_PLAY;
        effect(`ITEM_NONE);
        if (dut.angle !== 0) fail("angle not at zero");

        // Snap (SW15 = 1).
        sw[15] = 1; cycles(8);
        snap_click(1, 12'd1024, "normal board right did not step clockwise");
        effect(`ITEM_INVERT);
        snap_click(1, 12'd0, "inverted board right did not step counter-clockwise");
        snap_click(0, 12'd1024, "inverted board left did not step clockwise");
        snap_click(3, 12'd0, "inverted mouse right did not step counter-clockwise");
        snap_click(2, 12'd1024, "inverted mouse left did not step clockwise");
        // A press held while the effect ends changes direction: cancelled.
        press(1, 1); frame(); effect(`ITEM_NONE); press(1, 0); frame();
        if (dut.angle !== 12'd1024) fail("press held across the effect end was not cancelled");
        snap_click(1, 12'd2048, "board right did not return to clockwise after the effect");
        snap_click(3, 12'd3072, "mouse right did not return to clockwise after the effect");
        // ...and one held while the effect starts is cancelled too.
        press(3, 1); frame(); effect(`ITEM_INVERT); press(3, 0); frame();
        if (dut.angle !== 12'd3072) fail("press held across the effect start was not cancelled");
        effect(`ITEM_NONE);

        // Only FOG drives render's fog flag; INVERT and NONE do not.
        effect(`ITEM_FOG);
        if (dut.render_i.fog_en !== 1'b1) fail("FOG did not reach render.fog_en");
        effect(`ITEM_INVERT);
        if (dut.render_i.fog_en !== 1'b0) fail("INVERT drove render.fog_en");
        effect(`ITEM_NONE);
        if (dut.render_i.fog_en !== 1'b0) fail("NONE drove render.fog_en");

        // Top-level fog wiring: after the frame latch, a pixel far from the
        // ball is black and one 20 px away (inside the circle, outside the
        // ball) shows the map, at render's output in the real top.
        effect(`ITEM_FOG); frame();
        if (dut.render_i.fog_frame !== 1'b1) fail("FOG was not latched by render at the frame");
        force dut.ball_ov_i.ball_sx = 11'sd320; force dut.ball_ov_i.ball_sy = 11'sd240;
        force dut.active_video = 1'b1;
        force dut.pixel_x = 10'd200; force dut.pixel_y = 10'd240; cycles(3);
        if (dut.render_i.fog_clear !== dut.ball_ov_i.fog_clear || dut.render_i.fog_clear !== 1'b0 ||
            {dut.render_r, dut.render_g, dut.render_b} !== 12'h000)
            fail("pixel 120 px from the ball not fogged at the top");
        force dut.pixel_x = 10'd340; cycles(3);
        if (dut.render_i.fog_clear !== 1'b1 || dut.ball_on !== 1'b0 ||
            {dut.render_r, dut.render_g, dut.render_b} === 12'h000)
            fail("pixel 20 px from the ball fogged at the top");
        release dut.pixel_x; release dut.pixel_y; release dut.active_video;
        release dut.ball_ov_i.ball_sx; release dut.ball_ov_i.ball_sy;
        effect(`ITEM_NONE); frame();
        if (dut.render_i.fog_frame !== 1'b0) fail("fog stayed latched after the effect ended");

        // Smooth (SW15 = 0).
        sw[15] = 0; cycles(8);
        smooth_frame(1, 1, "normal smooth right did not turn clockwise");
        effect(`ITEM_INVERT);
        smooth_frame(1, -1, "inverted smooth right did not turn counter-clockwise");
        smooth_frame(0, 1, "inverted smooth left did not turn clockwise");
        smooth_frame(3, -1, "inverted smooth mouse right did not turn counter-clockwise");
        smooth_frame(2, 1, "inverted smooth mouse left did not turn clockwise");
        // Other effects do not invert.
        effect(`ITEM_FOG);
        smooth_frame(1, 1, "FOG inverted the controls");
        effect(`ITEM_NONE);
        smooth_frame(1, 1, "smooth right did not return to clockwise");
        smooth_frame(2, -1, "smooth mouse left did not return to counter-clockwise");
        // Both buttons still hold the angle while inverted.
        effect(`ITEM_INVERT);
        before = dut.angle; btnL = 1; btnR = 1; cycles(8); frame(); btnL = 0; btnR = 0; cycles(8);
        if (dut.angle !== before) fail("both buttons turned while inverted");

        release dut.item_i.active_effect;
        release dut.game_ctrl_i.game_state;
        $display("PASS: Story 9.4 invert controls for board and mouse buttons, snap and smooth, cancel on effect start and end, normal after the effect; only FOG drives fog_en, fog pixels at the top");
        $finish;
    end
    initial begin #2000000; fail("timeout"); end
endmodule
