`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_timer_warning_overlay;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] pixel_y = 10'd240;
    reg active_video = 1'b1;
    reg [`GAME_STATE_W-1:0] game_state = `ST_PLAY;
    reg [7:0] minutes_bcd = 8'h00;
    reg [7:0] seconds_bcd = 8'h31;
    wire warning_active;
    wire timer_flash_red;
    wire edge_glow;
    wire [3:0] edge_strength;
    reg [4:0] hud_n_cells = 5'd5;

    timer_warning_overlay #(.FRAMES_PER_HALF_SECOND(2)) dut (
        .clk(clk), .rst(rst), .frame_tick(frame_tick),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .game_state(game_state), .minutes_bcd(minutes_bcd),
        .seconds_bcd(seconds_bcd), .warning_active(warning_active),
        .timer_flash_red(timer_flash_red), .edge_glow(edge_glow),
        .edge_strength(edge_strength)
    );

    wire hud_panel, hud_accent, hud_text, hud_timer_line, hud_timer_red;
    wire hud_item_line, hud_debuff_line;
    game_status_hud hud_i (
        .clk(clk), .rst(rst), .pixel_x(10'd385), .pixel_y(10'd20),
        .active_video(1'b1), .game_state(game_state), .n_cells(hud_n_cells),
        .minutes_bcd(minutes_bcd), .seconds_bcd(seconds_bcd),
        .warning_active(warning_active), .timer_flash_red(timer_flash_red),
        .active_effect(`ITEM_NONE), .effect_seconds(7'd0),
        .panel_on(hud_panel), .accent_on(hud_accent), .text_on(hud_text),
        .timer_line(hud_timer_line), .timer_red(hud_timer_red),
        .item_line(hud_item_line), .debuff_line(hud_debuff_line)
    );

    task tick_frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
        end
    endtask

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL tb_timer_warning_overlay: %0s", message);
                $fatal(1);
            end
        end
    endtask

    integer i, stage_n;
    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);
        check(!warning_active, "warning started above 30 seconds");
        check(!edge_glow, "edge glow appeared above 30 seconds");

        // The threshold is the same for every supported stage size.
        for (stage_n = 5; stage_n <= 20; stage_n = stage_n + 5) begin
            hud_n_cells = stage_n;
            seconds_bcd = 8'h31;
            @(negedge clk);
            check(!warning_active, "warning started above 30 seconds for a stage size");
            seconds_bcd = 8'h30;
            @(negedge clk);
            check(warning_active, "warning did not start at 30 seconds for a stage size");
            check(hud_timer_line && !hud_timer_red,
                  "timer was not white at the 30-second warning start");
        end
        tick_frame(); tick_frame();
        @(negedge clk);
        check(edge_glow && edge_strength == 4'd1,
              "30-second edge pulse was not faint red");
        check(timer_flash_red && hud_timer_line && hud_timer_red,
              "timer did not flash red with the first half-second pulse");
        pixel_x = 10'd10;
        @(negedge clk);
        check(edge_glow && edge_strength == 4'd1,
              "faint warning did not reach the outer monitor edge");
        pixel_x = 10'd14;
        @(negedge clk);
        check(edge_glow && edge_strength == 4'd1,
              "thicker vignette did not reach the outermost 12..15 pixel band");
        pixel_x = 10'd16;
        @(negedge clk);
        check(!edge_glow && edge_strength == 4'd0,
              "vignette extended past the outermost 16-pixel band");

        pixel_x = 10'd6;
        seconds_bcd = 8'h28;
        @(negedge clk);
        check(edge_glow && edge_strength == 4'd1,
              "middle edge band did not attenuate the ramp");
        pixel_x = 10'd320;
        @(negedge clk);
        check(!edge_glow && edge_strength == 4'd0,
              "glow leaked into the visible maze interior");

        for (i = 0; i < 2; i = i + 1) tick_frame();
        @(negedge clk);
        check(!timer_flash_red && !hud_timer_red,
              "timer did not return to white with the next half-second pulse");
        for (i = 0; i < 2; i = i + 1) tick_frame();
        @(negedge clk);
        check(timer_flash_red && hud_timer_red,
              "timer did not flash red with the following half-second pulse");

        seconds_bcd = 8'h00;
        game_state = `ST_LOSE;
        pixel_x = 10'd0;
        @(negedge clk);
        check(warning_active, "zero-time lose state lost its final warning");
        check(edge_glow && edge_strength == 4'd15,
              "edge glow did not reach the same maximum at zero");

        game_state = `ST_PAUSED;
        @(negedge clk);
        check(!warning_active && !edge_glow,
              "warning kept pulsing after the game timer stopped");
        $display("PASS: timer warning threshold, pulse, ramp, and HUD flash");
        $finish;
    end
endmodule
