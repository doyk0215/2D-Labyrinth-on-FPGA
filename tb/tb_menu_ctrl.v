`timescale 1ns / 1ps

module tb_menu_ctrl;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg return_to_menu = 1'b0;
    reg menu_active = 1'b1;
    reg btn_up = 1'b0;
    reg btn_down = 1'b0;
    reg btn_confirm = 1'b0;
    reg btn_settings = 1'b0;
    wire start_game;
    wire [7:0] game_cfg;
    wire [511:0] status_text;
    wire selected_stage;
    wire settings_page;
    integer errors = 0;

    always #5 clk = ~clk;

    menu_ctrl dut (
        .clk(clk), .rst(rst), .return_to_menu(return_to_menu),
        .menu_active(menu_active), .btn_up(btn_up), .btn_down(btn_down),
        .btn_confirm(btn_confirm), .btn_settings(btn_settings),
        .start_game(start_game), .game_cfg(game_cfg),
        .status_text(status_text), .selected_stage(selected_stage),
        .settings_page(settings_page)
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

    task fail;
        input [511:0] message;
        begin
            $display("FAIL tb_menu_ctrl: %0s cfg=%h", message, game_cfg);
            errors = errors + 1;
        end
    endtask

    initial begin
        tick(2);
        rst = 1'b0;
        tick(1);
        if (selected_stage !== 1'b0 || settings_page !== 1'b0 ||
            game_cfg !== 8'h05 || status_text[7:0] !== "S" ||
            status_text[8*48 +: 8] !== "L")
            fail("default EASY stage menu/config incorrect");

        press_down;
        if (selected_stage !== 1'b1 || game_cfg !== 8'h1A ||
            status_text[8*32 +: 8] !== ">")
            fail("DOWN did not select HARD N=10 / restitution 1");

        btn_settings = 1'b1;
        tick(1);
        btn_settings = 1'b0;
        tick(1);
        if (!settings_page || selected_stage !== 1'b1 ||
            game_cfg !== 8'h1A || status_text[8*16 +: 8] !== "S")
            fail("settings page did not open while retaining the stage");

        press_up;
        if (game_cfg[7:6] !== 2'b10 ||
            status_text[8*(16+11) +: 8] !== "1")
            fail("UP did not select FAST 135 degrees/second");
        press_up;
        if (game_cfg[7:6] !== 2'b11)
            fail("UP did not select TURBO");
        press_up;
        if (game_cfg[7:6] !== 2'b01)
            fail("UP did not wrap TURBO to SLOW");
        press_up;
        if (game_cfg[7:6] !== 2'b00)
            fail("UP did not select NORMAL");
        press_down;
        if (game_cfg[7:6] !== 2'b01)
            fail("DOWN did not select SLOW");
        press_down;
        if (game_cfg[7:6] !== 2'b11)
            fail("DOWN did not wrap SLOW to TURBO");
        press_down;
        if (game_cfg[7:6] !== 2'b10)
            fail("DOWN did not select FAST");
        if (game_cfg[5:0] !== 6'h1A)
            fail("speed selection modified stage restitution or maze size");

        btn_confirm = 1'b1;
        tick(1);
        btn_confirm = 1'b0;
        tick(1);
        if (settings_page || start_game || selected_stage !== 1'b1 ||
            game_cfg !== 8'h9A)
            fail("BTNC did not return to the stage page without starting");

        btn_confirm = 1'b1;
        tick(1);
        btn_confirm = 1'b0;
        if (!start_game)
            fail("BTNC on stage page did not start the selected stage");
        tick(1);
        if (start_game)
            fail("start_game was not a one-cycle pulse");

        menu_active = 1'b0;
        return_to_menu = 1'b1;
        tick(1);
        return_to_menu = 1'b0;
        menu_active = 1'b1;
        if (selected_stage !== 1'b0 || settings_page ||
            game_cfg !== 8'h85)
            fail("return-to-menu did not reset stage and preserve speed");

        rst = 1'b1;
        tick(1);
        rst = 1'b0;
        if (game_cfg !== 8'h05)
            fail("power-on reset did not restore NORMAL speed");

        menu_active = 1'b0;
        btn_down = 1'b1;
        tick(2);
        btn_down = 1'b0;
        if (selected_stage !== 1'b0 || settings_page)
            fail("menu state changed outside MENU");

        if (errors == 0)
            $display("PASS: menu_ctrl stage selection, settings rates, retention, return, start, and reset");
        else
            $display("FAIL: menu_ctrl had %0d errors", errors);
        $finish;
    end
endmodule
