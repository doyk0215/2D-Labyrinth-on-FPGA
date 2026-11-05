`timescale 1ns / 1ps

// menu_ctrl: five stages EASY / MEDIUM / HARD / EPIC / CUSTOM, the live CUSTOM
// size N=5+SW3..SW0, the invalid-size error page, the rotation settings page,
// return to menu and reset. game_cfg is
// {custom, rot_speed_sel[1:0], restitution_sel[1:0], n_cells[4:0]}.
module tb_menu_ctrl;
    localparam integer HOLD = 20;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg return_to_menu = 1'b0;
    reg menu_active = 1'b1;
    reg btn_up = 1'b0;
    reg btn_down = 1'b0;
    reg btn_confirm = 1'b0;
    reg btn_settings = 1'b0;
    reg [4:0] custom_n = 5'd17;
    reg [47:0] highs = 48'h024_012_007_003; // EPIC 24, HARD 12, MEDIUM 7, EASY 3
    wire start_game;
    wire [9:0] game_cfg;
    wire [511:0] status_text;
    wire [2:0] selected_stage;
    wire settings_page;
    wire error_active;
    integer errors = 0;
    integer k, starts;

    always #5 clk = ~clk;
    always @(posedge clk) if (start_game) starts = starts + 1;

    menu_ctrl #(.ERROR_HOLD_CYCLES(HOLD)) dut (
        .clk(clk), .rst(rst), .return_to_menu(return_to_menu),
        .menu_active(menu_active), .btn_up(btn_up), .btn_down(btn_down),
        .btn_confirm(btn_confirm), .btn_settings(btn_settings),
        .custom_n(custom_n), .stage_high_scores_bcd(highs),
        .start_game(start_game), .game_cfg(game_cfg),
        .status_text(status_text), .selected_stage(selected_stage),
        .settings_page(settings_page), .error_active(error_active)
    );

    task tick;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) @(posedge clk);
            #1;
        end
    endtask

    task press_up;
        begin btn_up = 1'b1; tick(1); btn_up = 1'b0; tick(1); end
    endtask

    task press_down;
        begin btn_down = 1'b1; tick(1); btn_down = 1'b0; tick(1); end
    endtask

    task press_confirm;
        begin btn_confirm = 1'b1; tick(1); btn_confirm = 1'b0; tick(1); end
    endtask

    task fail;
        input [511:0] message;
        begin
            $display("FAIL tb_menu_ctrl: %0s cfg=%h stage=%0d", message, game_cfg, selected_stage);
            errors = errors + 1;
        end
    endtask

    function [127:0] row;
        input integer r;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                row[127 - 8 * i -: 8] = status_text[8 * (16 * r + i) +: 8];
        end
    endfunction

    task check_row;
        input integer r;
        input [127:0] expected;
        input [255:0] label_text;
        begin
            if (row(r) !== expected) begin
                $display("FAIL tb_menu_ctrl: %0s row %0d = \"%s\", expected \"%s\"",
                         label_text, r, row(r), expected);
                errors = errors + 1;
            end
        end
    endtask

    // Confirm CUSTOM with an invalid size: error page, no start, buttons
    // ignored, then the menu again with CUSTOM still selected.
    task check_invalid;
        input [4:0] value;
        input [127:0] line1;
        begin
            custom_n = value; tick(1);
            starts = 0;
            press_confirm;
            if (!error_active) fail("invalid CUSTOM size did not raise the error");
            check_row(0, "CUSTOM SIZE     ", "error page");
            check_row(1, line1, "error page size");
            check_row(2, "USE 5-20 ON     ", "error page");
            check_row(3, "SW3-SW0         ", "error page");
            press_up; press_confirm; btn_settings = 1'b1; tick(1); btn_settings = 1'b0; tick(1);
            if (selected_stage !== 3'd4 || settings_page) fail("buttons acted during the error page");
            custom_n = 5'd9; tick(1);
            check_row(1, line1, "error page keeps the rejected size");
            tick(HOLD);
            if (error_active) fail("error page did not end after ERROR_HOLD_CYCLES");
            if (starts != 0) fail("invalid CUSTOM size started a game");
            check_row(3, ">CUSTOM 5+4=9   ", "menu after the error");
        end
    endtask

    initial begin
        starts = 0;
        tick(2);
        rst = 1'b0;
        tick(1);
        if (selected_stage !== 2'd0 || settings_page !== 1'b0 || error_active ||
            game_cfg !== 10'h005)
            fail("default EASY stage config incorrect");
        check_row(0, ">EASY   HIGH=3  ", "default menu");
        check_row(1, " MEDIUM HIGH=7  ", "default menu");
        check_row(2, " HARD   HIGH=12 ", "default menu");
        check_row(3, " EPIC   HIGH=24 ", "default menu");
        highs = 48'h000_999_000_000; tick(1);
        check_row(2, " HARD   HIGH=999", "three-digit HIGH");
        highs = 48'h024_012_007_003; tick(1);

        press_down;
        if (selected_stage !== 2'd1 || game_cfg !== 10'h02A)
            fail("DOWN did not select MEDIUM N=10 / restitution 1");
        check_row(1, ">MEDIUM HIGH=7  ", "MEDIUM selected");
        check_row(0, " EASY   HIGH=3  ", "MEDIUM selected");

        press_down;
        if (selected_stage !== 2'd2 || game_cfg !== 10'h02F)
            fail("DOWN did not select HARD N=15 / restitution 1");

        press_down;
        if (selected_stage !== 3'd3 || game_cfg !== 10'h034)
            fail("DOWN did not select EPIC N=20 / restitution 1");
        check_row(2, ">EPIC   HIGH=24 ", "EPIC selected and OLED scrolled");
        press_down;
        if (selected_stage !== 3'd4 || game_cfg !== 10'h231)
            fail("DOWN did not select CUSTOM N=17 / restitution 1");
        check_row(3, ">CUSTOM 5+12=17 ", "CUSTOM selected");
        // The CUSTOM size and its row follow the switches live.
        custom_n = 5'd5; tick(1);
        if (game_cfg !== 10'h205) fail("CUSTOM N=5 config (restitution 0) incorrect");
        check_row(3, ">CUSTOM 5+0=5   ", "live CUSTOM size");
        custom_n = 5'd20; tick(1);
        check_row(3, ">CUSTOM 5+15=20 ", "live CUSTOM maximum");

        btn_up=1; btn_down=1; tick(1); btn_up=0; btn_down=0; tick(1);
        if(selected_stage !== 3'd4) fail("simultaneous UP/DOWN changed selection");
        press_down;
        if(selected_stage !== 2'd0) fail("DOWN did not wrap CUSTOM to EASY");
        press_up;
        if(selected_stage !== 3'd4) fail("UP did not wrap EASY to CUSTOM");
        press_up;
        if(selected_stage !== 3'd3) fail("UP did not return CUSTOM to EPIC");
        press_up; press_up; press_up;
        if(selected_stage !== 2'd0) fail("UP did not return HARD to EASY");

        // Invalid CUSTOM sizes: below 5 and above 20.
        press_up;
        check_invalid(5'd0,  "INVALID: N=0    ");
        check_invalid(5'd1,  "INVALID: N=1    ");
        check_invalid(5'd4,  "INVALID: N=4    ");
        check_invalid(5'd21, "INVALID: N=21   ");
        check_invalid(5'd25, "INVALID: N=25   ");
        check_invalid(5'd31, "INVALID: N=31   ");

        // Valid CUSTOM sizes 5..20 start at once with their own config.
        for (k = 5; k <= 20; k = k + 1) begin
            custom_n = k; tick(1);
            starts = 0;
            btn_confirm = 1'b1; tick(1); btn_confirm = 1'b0;
            if (!start_game || error_active || game_cfg[9] !== 1'b1 || game_cfg[4:0] !== k ||
                game_cfg[6:5] !== ((k <= 5) ? 2'b00 : 2'b01))
                fail("valid CUSTOM size did not start with its config");
            tick(1);
            if (start_game) fail("start_game was not a one-cycle pulse");
        end

        // Settings page: rotation speed in cfg[8:7], stage fields untouched.
        press_up; press_up; press_up;               // MEDIUM
        btn_settings = 1'b1; tick(1); btn_settings = 1'b0; tick(1);
        if (!settings_page || selected_stage !== 2'd1 || game_cfg !== 10'h02A ||
            status_text[8*16 +: 8] !== "S")
            fail("settings page did not open while retaining the stage");
        press_up;
        if (game_cfg[8:7] !== 2'b10 || status_text[8*(16+11) +: 8] !== "1")
            fail("UP did not select FAST 135 degrees/second");
        press_up;
        if (game_cfg[8:7] !== 2'b11) fail("UP did not select TURBO");
        press_up;
        if (game_cfg[8:7] !== 2'b01) fail("UP did not wrap TURBO to SLOW");
        press_up;
        if (game_cfg[8:7] !== 2'b00) fail("UP did not select NORMAL");
        press_down;
        if (game_cfg[8:7] !== 2'b01) fail("DOWN did not select SLOW");
        press_down;
        if (game_cfg[8:7] !== 2'b11) fail("DOWN did not wrap SLOW to TURBO");
        press_down;
        if (game_cfg[8:7] !== 2'b10) fail("DOWN did not select FAST");
        if ({game_cfg[9], game_cfg[6:0]} !== 8'h2A)
            fail("speed selection modified the stage fields");

        press_confirm;
        if (settings_page || selected_stage !== 2'd1 || game_cfg !== 10'h12A)
            fail("BTNC did not return to the stage page without starting");

        btn_confirm = 1'b1; tick(1); btn_confirm = 1'b0;
        if (!start_game) fail("BTNC on stage page did not start the selected stage");
        tick(1);

        menu_active = 1'b0;
        return_to_menu = 1'b1;
        tick(1);
        return_to_menu = 1'b0;
        menu_active = 1'b1;
        if (selected_stage !== 2'd0 || settings_page || game_cfg !== 10'h105)
            fail("return-to-menu did not reset stage and preserve speed");

        rst = 1'b1;
        tick(1);
        rst = 1'b0;
        if (game_cfg !== 10'h005) fail("power-on reset did not restore NORMAL speed");

        menu_active = 1'b0;
        btn_down = 1'b1;
        tick(2);
        btn_down = 1'b0;
        if (selected_stage !== 2'd0 || settings_page)
            fail("menu state changed outside MENU");

        if (errors == 0)
            $display("PASS: menu_ctrl five stages, separate HIGH records, CUSTOM 5..20 offsets, error page, settings, retention, return, start and reset");
        else
            $display("FAIL: menu_ctrl had %0d errors", errors);
        $finish;
    end
endmodule
