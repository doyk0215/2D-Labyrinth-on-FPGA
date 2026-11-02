`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_oled_status_text;

    reg [511:0] menu_text = 512'd0;
    reg [`GAME_STATE_W-1:0] game_state = `ST_MENU;
    reg [7:0] active_game_cfg = 8'h05;
    reg [7:0] elapsed_minutes_bcd = 8'h00;
    reg [7:0] elapsed_seconds_bcd = 8'h00;
    reg [3:0] item_effect=`ITEM_NONE;
    reg [6:0] item_seconds=0;
    wire [511:0] status_text;
    integer errors = 0;
    integer seconds_value;
    reg [7:0] tens_char, units_char;

    oled_status_text dut (
        .active_effect(item_effect), .effect_seconds(item_seconds),
        .menu_text(menu_text), .game_state(game_state),
        .active_game_cfg(active_game_cfg),
        .elapsed_minutes_bcd(elapsed_minutes_bcd),
        .elapsed_seconds_bcd(elapsed_seconds_bcd),
        .status_text(status_text)
    );

    task check_char;
        input integer byte_index;
        input [7:0] expected;
        input [255:0] label_text;
        reg [7:0] actual;
        begin
            actual = status_text[8 * byte_index +: 8];
            if (actual !== expected) begin
                $display("FAIL tb_oled_status_text %0s at byte %0d: got '%c', expected '%c'",
                         label_text, byte_index, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_item_row;
        input [127:0] expected;
        integer j;
        begin for(j=0;j<16;j=j+1) check_char(32+j,expected[127-j*8-:8],"item status row"); end
    endtask
    initial begin
        menu_text[7:0] = "M";
        #1;
        if (status_text !== menu_text) begin
            $display("FAIL tb_oled_status_text: MENU did not pass through the existing menu page");
            errors = errors + 1;
        end

        active_game_cfg = 8'h05;
        elapsed_minutes_bcd = 8'h09;
        elapsed_seconds_bcd = 8'h42;
        game_state = `ST_PLAY;
        #1;
        check_char(0, "S", "stage-one header");
        check_char(6, "1", "stage-one number");
        check_char(8, "E", "easy label");
        check_char(16, "T", "time row");
        check_char(21, "0", "minutes tens");
        check_char(22, "9", "minutes units");
        check_char(23, ":", "time separator");
        check_char(24, "4", "seconds tens");
        check_char(25, "2", "seconds units");
        check_char(32, "P", "PLAY status");

        active_game_cfg = 8'h9A;
        #1;
        check_char(6, "2", "stage-two number from active configuration");
        check_char(8, "H", "hard label");

        game_state = `ST_WIN;
        #1;
        check_char(32, "Y", "WIN status");
        check_char(21, "0", "final time retained on WIN");

        active_game_cfg = 8'h9F;
        #1;
        check_char(6, "3", "HUGE stage number in WIN");
        check_char(8, "H", "HUGE stage label in WIN");
        check_char(10, "G", "HUGE label is distinct from HARD");
        check_char(25, "2", "HUGE preserves timer formatting");
        game_state = `ST_PLAY;
        #1;
        check_char(6, "3", "HUGE stage number in PLAY");
        check_char(32, "P", "HUGE PLAY status");

        game_state = `ST_GENERATE;
        #1;
        check_char(32, "G", "generation status");
        check_char(16, "T", "generation timer reset display");
        check_char(21, "0", "generation time starts at zero");

        // LOSE has its own page rather than aliasing the stage menu. Even
        // nonzero input time cannot leak stale remaining time into TIME UP.
        game_state = `ST_LOSE;
        #1;
        check_char(6, "3", "HUGE retained in LOSE");
        check_char(21, "0", "LOSE zero minutes tens");
        check_char(22, "0", "LOSE zero minutes units");
        check_char(24, "0", "LOSE zero seconds tens");
        check_char(25, "0", "LOSE zero seconds units");
        check_char(32, "T", "TIME UP title");
        check_char(37, "U", "TIME UP word");
        check_char(38, "P", "TIME UP last letter");
        check_char(48, "B", "automatic menu return hint");
        active_game_cfg = 8'h05; #1;
        check_char(6, "1", "EASY retained in LOSE");
        active_game_cfg = 8'h1A; #1;
        check_char(6, "2", "HARD retained in LOSE");
        game_state = `ST_MENU; #1;
        if (status_text !== menu_text) begin
            $display("FAIL tb_oled_status_text: leaving LOSE did not restore the menu");
            errors = errors + 1;
        end

        game_state=`ST_PLAY; item_effect=`ITEM_LOW_GRAV;item_seconds=8;#1;
        check_item_row("ITEM:LOW GRAV 08");
        item_effect=`ITEM_REVERSE_GRAV;item_seconds=12;#1;
        check_item_row("ITEM:REV GRAV 12");
        item_effect=`ITEM_FOG;item_seconds=99;#1;
        check_item_row("ITEM:FOG      99");
        // Story 9.4: every displayable value, against /10 and %10 here.
        for(seconds_value=1;seconds_value<100;seconds_value=seconds_value+1) begin
            item_seconds=seconds_value;#1;
            tens_char=8'h30+seconds_value/10; units_char=8'h30+seconds_value%10;
            check_item_row({"ITEM:FOG      ", tens_char, units_char});
        end
        item_seconds=0;#1;check_item_row("PLAYING         ");
        item_effect=`ITEM_NONE;item_seconds=8;#1;check_item_row("PLAYING         ");
        game_state=`ST_WIN;item_effect=`ITEM_LOW_GRAV;#1;
        check_item_row("YOU WIN         ");
        game_state=`ST_LOSE;#1;check_item_row("TIME UP         ");
        if (errors == 0)
            $display("PASS: OLED status formatter menu passthrough, active stage, BCD time, WIN, and GENERATE");
        else
            $display("FAIL: OLED status formatter had %0d errors", errors);
        $finish;
    end
endmodule
