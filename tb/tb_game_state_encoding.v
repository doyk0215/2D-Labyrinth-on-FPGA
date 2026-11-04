`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Shared state codes must survive every state port without aliasing. Code 5 is
// now the dedicated PAUSED state; codes 6 and 7 remain reserved.
module tb_game_state_encoding;
    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;
    reg frame_tick = 1'b0, start_game = 1'b0, gen_done = 1'b0, in_goal = 1'b0;
    wire [`GAME_STATE_W-1:0] ctrl_state;
    wire [9:0] active_cfg;
    wire phys_en;
    game_ctrl #(.START_IN_MENU(1'b1), .WIN_HOLD_FRAMES(2)) ctrl_i (
        .clk(clk), .rst(rst), .full_reset(1'b0), .frame_tick(frame_tick), .start_game(start_game),
        .game_cfg(10'h145), .regen_button(1'b0), .pause_button(1'b0),
        .pause_resume(1'b0), .pause_restart(1'b0),
        .gen_busy(1'b0), .gen_done(gen_done),
        .time_up(1'b0), .in_goal(in_goal), .game_state(ctrl_state), .active_game_cfg(active_cfg),
        .gen_start(), .seed_capture(), .phys_init(), .phys_en(phys_en)
    );
    reg timer_init = 1'b0;
    reg timer_maze_pixel_visible = 1'b0;
    reg timer_player_action = 1'b0;
    reg [`GAME_STATE_W-1:0] state_in = `ST_MENU;
    wire [7:0] minutes, seconds;
    game_timer #(.CLK_HZ(2)) timer_i (
        .clk(clk), .rst(rst), .preserve_time(1'b0),
        .maze_pixel_visible(timer_maze_pixel_visible),
        .player_action(timer_player_action), .game_state(state_in),
        .phys_init(timer_init), .n_cells(5'd5), .time_up(), .time_bonus_pulse(1'b0),
        .elapsed_minutes_bcd(minutes), .elapsed_seconds_bcd(seconds)
    );
    reg [511:0] menu_text = 512'h4d; // distinct from PLAY/WIN status pages
    wire [511:0] status_text;
    oled_status_text status_i (
        .active_effect(`ITEM_NONE), .effect_seconds(7'd0),
        .menu_text(menu_text), .game_state(state_in), .active_game_cfg(10'h145),
        .elapsed_minutes_bcd(minutes), .elapsed_seconds_bcd(seconds),
        .pause_selection(2'd0), .status_text(status_text)
    );
    wire [3:0] r, g, b;
    render render_i (
        .clk(clk), .rst(rst), .ce_pix(1'b0), .frame_tick(frame_tick), .game_state(state_in), .time_min_bcd(8'h00), .time_sec_bcd(8'h00), .n_cells(5'd10), .cam_x(18'sd0), .cam_y(18'sd0),
        .angle(12'd0), .sin_q(16'sd0), .cos_q(16'sd16384),
        .pixel_x(10'd156), .pixel_y(10'd212), .active_video(1'b1),
        .hsync_in(1'b1), .vsync_in(1'b1), .maze_raddr(), .maze_rdata(1'b0),
        .start_col(6'd19), .start_row(6'd19), .goal_col(6'd1), .goal_row(6'd1),
        .box_cols(36'd0), .box_rows(36'd0), .box_valid(4'b0000), .box_visible(4'b1111),
        .ball_on(1'b1), .fog_en(1'b0), .fog_clear(1'b0), .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(), .vga_vs(),
        .sin_snap(), .cos_snap()
    );
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3)) top_i (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnD(1'b0), .btnL(1'b0), .btnR(1'b0),
        .sw(16'h4000), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    localparam [`GAME_STATE_W-1:0] UNUSED_WITH_WIN_BITS = 3'b111;
    task fail;
        input [511:0] message;
        begin $display("FAIL game state encoding: %0s", message); $finish; end
    endtask
    task frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask
    task visible_pixel;
        begin
            @(negedge clk); timer_maze_pixel_visible = 1'b1; timer_player_action = 1'b1;
            @(negedge clk); timer_player_action = 1'b0; timer_maze_pixel_visible = 1'b0;
        end
    endtask

    integer code;
    reg [7:0] frozen_minutes, frozen_seconds;
    initial begin
        if (`GAME_STATE_W != 3 || `ST_MENU != 3'd0 || `ST_GENERATE != 3'd1 ||
            `ST_PLAY != 3'd2 || `ST_WIN != 3'd3 || `ST_LOSE != 3'd4 ||
            `ST_PAUSED != 3'd5)
            fail("shared codes changed an established state or omitted PAUSED");
        repeat (8) @(negedge clk);
        rst = 1'b0;
        if (ctrl_state !== `ST_MENU) fail("reset did not select shared MENU");
        start_game = 1'b1;
        frame(); start_game = 1'b0;
        if (ctrl_state !== `ST_GENERATE || active_cfg !== 10'h145)
            fail("MENU start changed the 10-bit game configuration");
        repeat (5) @(negedge clk);
        gen_done = 1'b1;
        frame(); gen_done = 1'b0;
        if (ctrl_state !== `ST_PLAY || !phys_en) fail("generation did not enter shared PLAY");
        in_goal = 1'b1;
        frame(); in_goal = 1'b0;
        if (ctrl_state !== `ST_WIN || phys_en) fail("goal did not enter shared WIN");
        frame();
        if (ctrl_state !== `ST_WIN) fail("WIN pause changed during state migration");
        frame();
        if (ctrl_state !== `ST_GENERATE || active_cfg !== 10'h145)
            fail("replay changed state behaviour or the latched game configuration");

        state_in = `ST_PLAY;
        timer_init = 1'b1;
        @(negedge clk); timer_init = 1'b0;
        visible_pixel();
        repeat (4) @(negedge clk);
        if (minutes !== 8'h00 || seconds !== 8'h58) fail("valid PLAY did not decrement the timer");
        frozen_minutes = minutes; frozen_seconds = seconds;
        for (code = 4; code < 8; code = code + 1) begin
            state_in = code;
            force top_i.game_ctrl_i.game_state = state_in;
            #1;
            if (top_i.game_state !== state_in ||
                top_i.render_i.game_state !== state_in ||
                top_i.elapsed_timer_i.game_state !== state_in ||
                top_i.oled_status_i.game_state !== state_in)
                fail("top-level state bus or a consumer truncated the high bit");
            if (top_i.menu_active || top_i.phys_en ||
                top_i.render_enable !== ((code == `ST_LOSE) || (code == `ST_PAUSED)))
                fail("state aliased MENU/PLAY or failed to enable its required VGA output");
            frame();
            if (minutes !== frozen_minutes || seconds !== frozen_seconds)
                fail("reserved code aliased PLAY in game_timer");
            if (code == `ST_LOSE) begin
                // Status line (row 3) of the stage / LEVELS COMPLETED page.
                if (status_text[48*8 +: 8] !== "T" || status_text[53*8 +: 8] !== "U")
                    fail("LOSE did not select its dedicated OLED status page");
            end else if (code == `ST_PAUSED) begin
                if (status_text[0 +: 8] !== "P" || status_text[16*8 +: 8] !== ">")
                    fail("PAUSED did not select the pause menu with RESUME selected");
            end else if (status_text !== menu_text)
                fail("reserved code aliased a live OLED status page");
            if (render_i.win_frame) fail("high-bit state aliased WIN in the renderer");
            if (code == `ST_LOSE) begin
                if (!render_i.lose_frame || {r,g,b} !== 12'hfff)
                    fail("LOSE did not select TIME UP in the renderer");
            end else if (code == `ST_PAUSED) begin
                if (!render_i.pause_frame || {r,g,b} !== 12'h013)
                    fail("PAUSED did not select the VGA pause panel");
            end else if (render_i.lose_frame || {r,g,b} !== 12'hfc0)
                fail("reserved code aliased a result overlay in the renderer");
        end
        release top_i.game_ctrl_i.game_state;
        state_in = `ST_WIN;
        frame();
        if (!render_i.win_frame || {r,g,b} !== 12'hfff || status_text[48*8 +: 8] !== "Y")
            fail("valid WIN no longer selects VGA and OLED win indications");

        // Code 7 remains unused and keeps the controller's recovery path.
        @(negedge clk); force ctrl_i.game_state = UNUSED_WITH_WIN_BITS;
        #1;
        if (phys_en) fail("physics was enabled for an unused controller state");
        release ctrl_i.game_state;
        @(posedge clk); #1;
        if (ctrl_state !== `ST_GENERATE) fail("unused state was truncated to WIN instead of recovering");
        $display("PASS: shared game state - 3-bit ports, v1 flow, 10-bit configuration, and no high-bit aliases");
        $finish;
    end
    initial begin #1000000; fail("timeout"); end
endmodule
