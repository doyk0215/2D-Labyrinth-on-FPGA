`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Story 6.1: codes with bit 2 set must survive every state port and must not
// alias the v1 MENU/PLAY/WIN behaviours when LOSE is introduced later.
module tb_game_state_encoding;
    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;
    reg frame_tick = 1'b0, start_game = 1'b0, gen_done = 1'b0, in_goal = 1'b0;
    wire [`GAME_STATE_W-1:0] ctrl_state;
    wire [7:0] active_cfg;
    wire phys_en;
    game_ctrl #(.START_IN_MENU(1'b1), .WIN_HOLD_FRAMES(2)) ctrl_i (
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .start_game(start_game),
        .game_cfg(8'ha5), .regen_button(1'b0), .gen_busy(1'b0), .gen_done(gen_done),
        .in_goal(in_goal), .game_state(ctrl_state), .active_game_cfg(active_cfg),
        .gen_start(), .seed_capture(), .phys_init(), .phys_en(phys_en)
    );
    reg [`GAME_STATE_W-1:0] state_in = `ST_MENU;
    wire [7:0] minutes, seconds;
    game_timer #(.CLK_HZ(2)) timer_i (
        .clk(clk), .rst(rst), .game_state(state_in), .phys_init(1'b0),
        .elapsed_minutes_bcd(minutes), .elapsed_seconds_bcd(seconds)
    );
    reg [511:0] menu_text = 512'h4d; // distinct from PLAY/WIN status pages
    wire [511:0] status_text;
    oled_status_text status_i (
        .menu_text(menu_text), .game_state(state_in), .active_game_cfg(8'ha5),
        .elapsed_minutes_bcd(minutes), .elapsed_seconds_bcd(seconds), .status_text(status_text)
    );
    wire [3:0] r, g, b;
    render render_i (
        .clk(clk), .rst(rst), .ce_pix(1'b0), .frame_tick(frame_tick), .game_state(state_in),
        .angle(12'd0), .sin_q(16'sd0), .cos_q(16'sd16384),
        .pixel_x(10'd156), .pixel_y(10'd212), .active_video(1'b1),
        .hsync_in(1'b1), .vsync_in(1'b1), .maze_raddr(), .maze_rdata(1'b0),
        .start_col(5'd19), .start_row(5'd19), .goal_col(5'd1), .goal_row(5'd1),
        .ball_on(1'b1), .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(), .vga_vs(),
        .sin_snap(), .cos_snap()
    );
    tri1 ps2_clk, ps2_data;
    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3)) top_i (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnD(1'b0), .btnL(1'b0), .btnR(1'b0),
        .sw(16'h0001), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    localparam [`GAME_STATE_W-1:0] UNUSED_WITH_WIN_BITS = 3'b111;
    task fail;
        input [511:0] message;
        begin $display("FAIL game state encoding: %0s", message); $fatal(1); end
    endtask
    task frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    integer code;
    reg [7:0] frozen_minutes, frozen_seconds;
    initial begin
        if (`GAME_STATE_W != 3 || `ST_MENU != 3'd0 || `ST_GENERATE != 3'd1 ||
            `ST_PLAY != 3'd2 || `ST_WIN != 3'd3 || `ST_LOSE != 3'd4)
            fail("shared codes changed the v1 encoding or did not reserve LOSE");
        repeat (8) @(negedge clk);
        rst = 1'b0;
        if (ctrl_state !== `ST_MENU) fail("reset did not select shared MENU");
        start_game = 1'b1;
        frame(); start_game = 1'b0;
        if (ctrl_state !== `ST_GENERATE || active_cfg !== 8'ha5)
            fail("MENU start changed the 8-bit game configuration");
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
        if (ctrl_state !== `ST_GENERATE || active_cfg !== 8'ha5)
            fail("replay changed state behaviour or the latched game configuration");

        state_in = `ST_PLAY;
        repeat (4) @(negedge clk);
        if (seconds !== 8'h02) fail("valid PLAY did not advance the timer");
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
            if (top_i.menu_active || top_i.render_enable || top_i.phys_en)
                fail("reserved code aliased MENU, PLAY, or WIN in the top level");
            frame();
            if (minutes !== frozen_minutes || seconds !== frozen_seconds)
                fail("reserved code aliased PLAY in game_timer");
            if (status_text !== menu_text) fail("reserved code aliased a live OLED status page");
            if (render_i.win_frame || {r,g,b} !== 12'hfc0)
                fail("reserved code aliased WIN in the renderer");
        end
        release top_i.game_ctrl_i.game_state;
        state_in = `ST_WIN;
        frame();
        if (!render_i.win_frame || {r,g,b} !== 12'hfff || status_text[32*8 +: 8] !== "Y")
            fail("valid WIN no longer selects VGA and OLED win indications");

        // LOSE is reserved, not a new controller transition in Story 6.1.
        // Unimplemented encodings keep the controller's existing recovery path.
        @(negedge clk); force ctrl_i.game_state = UNUSED_WITH_WIN_BITS;
        #1;
        if (phys_en) fail("physics was enabled for an unused controller state");
        release ctrl_i.game_state;
        @(posedge clk); #1;
        if (ctrl_state !== `ST_GENERATE) fail("unused state was truncated to WIN instead of recovering");
        $display("PASS: shared game state - 3-bit ports, v1 flow, 8-bit configuration, and no high-bit aliases");
        $finish;
    end
    initial begin #1000000; fail("timeout"); end
endmodule
