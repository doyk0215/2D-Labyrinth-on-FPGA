`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// The in-game OLED page is four rows: the stage name, "LEVELS COMPLETED",
// the BCD count and a status line. The timer and item effect are on the VGA
// and seven-segment displays, so they never reach this page.
module tb_oled_status_text;

    reg [511:0] menu_text = 512'd0;
    reg         instructions_active = 1'b0;
    reg [2:0]   instructions_scroll = 3'd0;
    reg [`GAME_STATE_W-1:0] game_state = `ST_MENU;
    reg [9:0] active_game_cfg = 10'h005;
    reg [7:0] elapsed_minutes_bcd = 8'h00;
    reg [7:0] elapsed_seconds_bcd = 8'h00;
    reg [`ITEM_EFFECT_W-1:0] item_effect = `ITEM_NONE;
    reg [6:0] item_seconds = 0;
    reg [11:0] levels_completed_bcd = 12'h000;
    reg [1:0] pause_selection = 2'd0;
    wire [511:0] status_text;
    integer errors = 0;

    oled_status_text dut (
        .menu_text(menu_text),
        .instructions_active(instructions_active),
        .instructions_scroll(instructions_scroll),
        .game_state(game_state),
        .active_game_cfg(active_game_cfg),
        .elapsed_minutes_bcd(elapsed_minutes_bcd),
        .elapsed_seconds_bcd(elapsed_seconds_bcd),
        .active_effect(item_effect), .effect_seconds(item_seconds),
        .levels_completed_bcd(levels_completed_bcd),
        .pause_selection(pause_selection),
        .status_text(status_text)
    );

    task check_row;
        input integer row;
        input [127:0] expected;
        input [255:0] label_text;
        integer j;
        reg [127:0] actual;
        begin
            for (j = 0; j < 16; j = j + 1)
                actual[127 - 8 * j -: 8] = status_text[8 * (16 * row + j) +: 8];
            if (actual !== expected) begin
                $display("FAIL tb_oled_status_text %0s row %0d: got '%s', expected '%s'",
                         label_text, row, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_game_page;
        input [127:0] stage;
        input [127:0] count;
        input [127:0] status;
        input [255:0] label_text;
        begin
            check_row(0, stage, label_text);
            check_row(1, "LEVELS COMPLETED", label_text);
            check_row(2, count, label_text);
            check_row(3, status, label_text);
        end
    endtask

    initial begin
        menu_text[7:0] = "M";
        #1;
        if (status_text !== menu_text) begin
            $display("FAIL tb_oled_status_text: MENU did not pass through the existing menu page");
            errors = errors + 1;
        end

        // Instructions replace the menu page; four scroll positions.
        instructions_active = 1'b1; #1;
        check_row(0, "INSTRUCTIONS 1/4", "instructions page 1");
        check_row(1, "LMB/BTN L: CCW  ", "instructions page 1");
        check_row(3, "SW15: 90DEG SNAP", "instructions page 1");
        instructions_scroll = 3'd1; #1;
        check_row(0, "INSTRUCTIONS 2/4", "instructions page 2");
        check_row(2, "SW15: 90DEG SNAP", "instructions page 2");
        instructions_scroll = 3'd3; #1;
        check_row(0, "INSTRUCTIONS 4/4", "instructions page 4");
        check_row(3, "BTNC: MAIN MENU ", "instructions page 4");
        instructions_active = 1'b0; instructions_scroll = 3'd0; #1;
        if (status_text !== menu_text) begin
            $display("FAIL tb_oled_status_text: closing instructions did not restore the menu");
            errors = errors + 1;
        end

        // Stage names and the status line for each game state. The timer
        // and item inputs are set but must not show.
        elapsed_minutes_bcd = 8'h09; elapsed_seconds_bcd = 8'h42;
        item_effect = `ITEM_FOG; item_seconds = 7'd8;
        levels_completed_bcd = 12'h000;
        game_state = `ST_GENERATE; #1;
        check_game_page("STAGE 1 EASY    ", "N: 000          ", "GENERATING...   ", "EASY GENERATE");
        game_state = `ST_PLAY; #1;
        check_game_page("STAGE 1 EASY    ", "N: 000          ", "BTNC MENU       ", "EASY PLAY");

        active_game_cfg = 10'h12A; levels_completed_bcd = 12'h007; #1;  // MEDIUM, FAST
        check_game_page("STAGE 2 MEDIUM  ", "N: 007          ", "BTNC MENU       ", "MEDIUM PLAY");
        game_state = `ST_WIN; levels_completed_bcd = 12'h123; #1;
        check_game_page("STAGE 2 MEDIUM  ", "N: 123          ", "YOU WIN         ", "MEDIUM WIN");

        active_game_cfg = 10'h02F; #1;
        check_game_page("STAGE 3 HARD    ", "N: 123          ", "YOU WIN         ", "HARD WIN");
        game_state = `ST_LOSE; #1;
        check_game_page("STAGE 3 HARD    ", "N: 123          ", "TIME UP         ", "HARD LOSE");

        // CUSTOM shows its size, never a preset name, even at N = 5/10/15.
        active_game_cfg = 10'h231; #1;   // N = 17
        check_row(0, "CUSTOM N=17     ", "CUSTOM N=17");
        active_game_cfg = 10'h20A; #1;   // N = 10 is not MEDIUM
        check_row(0, "CUSTOM N=10     ", "CUSTOM N=10");
        active_game_cfg = 10'h234; #1;
        check_row(0, "CUSTOM N=20     ", "CUSTOM N=20");
        active_game_cfg = 10'h202; #1;
        check_row(0, "CUSTOM N=2      ", "CUSTOM N=2");
        active_game_cfg = 10'h007; #1;   // not a preset size
        check_row(0, "STAGE ?         ", "unknown stage");

        // Pause page: the selection marker moves through the three entries.
        game_state = `ST_PAUSED; pause_selection = 2'd0; #1;
        check_row(0, "PAUSED          ", "pause title");
        check_row(1, ">RESUME         ", "pause RESUME selected");
        check_row(2, " RESTART        ", "pause RESUME selected");
        check_row(3, " MENU           ", "pause RESUME selected");
        pause_selection = 2'd1; #1;
        check_row(1, " RESUME         ", "pause RESTART selected");
        check_row(2, ">RESTART        ", "pause RESTART selected");
        pause_selection = 2'd2; #1;
        check_row(2, " RESTART        ", "pause MENU selected");
        check_row(3, ">MENU           ", "pause MENU selected");

        game_state = `ST_MENU; #1;
        if (status_text !== menu_text) begin
            $display("FAIL tb_oled_status_text: leaving the game did not restore the menu");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: OLED status formatter menu passthrough, instructions 1-4/4, stage names incl. CUSTOM, levels completed, GENERATE/PLAY/WIN/LOSE status, pause selection, no timer or item text");
        else
            $display("FAIL: OLED status formatter had %0d errors", errors);
        $finish;
    end
endmodule
