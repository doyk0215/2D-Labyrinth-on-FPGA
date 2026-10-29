`timescale 1ns / 1ps

module tb_oled_status_text;
    localparam [1:0] MENU = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY = 2'b10;
    localparam [1:0] WIN = 2'b11;

    reg [511:0] menu_text = 512'd0;
    reg [1:0] game_state = MENU;
    reg [7:0] active_game_cfg = 8'h05;
    reg [7:0] elapsed_minutes_bcd = 8'h00;
    reg [7:0] elapsed_seconds_bcd = 8'h00;
    wire [511:0] status_text;
    integer errors = 0;

    oled_status_text dut (
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
        game_state = PLAY;
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

        game_state = WIN;
        #1;
        check_char(32, "Y", "WIN status");
        check_char(21, "0", "final time retained on WIN");

        game_state = GENERATE;
        #1;
        check_char(32, "G", "generation status");
        check_char(16, "T", "generation timer reset display");
        check_char(21, "0", "generation time starts at zero");

        if (errors == 0)
            $display("PASS: OLED status formatter menu passthrough, active stage, BCD time, WIN, and GENERATE");
        else
            $display("FAIL: OLED status formatter had %0d errors", errors);
        $finish;
    end
endmodule
