`timescale 1ns / 1ps

module tb_menu_ctrl;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg menu_active = 1'b1;
    reg btn_up = 1'b0;
    reg btn_down = 1'b0;
    reg btn_confirm = 1'b0;
    wire start_game;
    wire [7:0] game_cfg;
    wire [511:0] status_text;
    wire selected_stage;
    integer errors = 0;

    always #5 clk = ~clk;

    menu_ctrl dut (
        .clk(clk), .rst(rst), .menu_active(menu_active),
        .btn_up(btn_up), .btn_down(btn_down), .btn_confirm(btn_confirm),
        .start_game(start_game), .game_cfg(game_cfg),
        .status_text(status_text), .selected_stage(selected_stage)
    );

    task tick;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        tick(2);
        rst = 1'b0;
        tick(1);
        if (selected_stage !== 1'b0 || game_cfg !== 8'h05 ||
            status_text[7:0] !== "S" || status_text[8*16 +: 8] !== ">") begin
            $display("FAIL: default EASY stage config/menu incorrect");
            errors = errors + 1;
        end

        btn_down = 1'b1;
        tick(1);
        btn_down = 1'b0;
        tick(1);
        if (selected_stage !== 1'b1 || game_cfg !== 8'h1A ||
            status_text[8*32 +: 8] !== ">") begin
            $display("FAIL: DOWN did not select HARD N=10 / restitution 1");
            errors = errors + 1;
        end

        btn_up = 1'b1;
        tick(1);
        btn_up = 1'b0;
        tick(1);
        if (selected_stage !== 1'b0 || game_cfg[3:0] !== 4'd5) begin
            $display("FAIL: UP did not return to EASY N=5");
            errors = errors + 1;
        end

        btn_confirm = 1'b1;
        tick(1);
        btn_confirm = 1'b0;
        if (start_game !== 1'b1) begin
            $display("FAIL: confirm did not generate a start pulse");
            errors = errors + 1;
        end
        tick(1);
        if (start_game !== 1'b0) begin
            $display("FAIL: start_game was not a one-cycle pulse");
            errors = errors + 1;
        end

        menu_active = 1'b0;
        btn_down = 1'b1;
        tick(2);
        btn_down = 1'b0;
        if (selected_stage !== 1'b0) begin
            $display("FAIL: menu selection changed outside MENU");
            errors = errors + 1;
        end

        rst = 1'b1;
        tick(1);
        if (selected_stage !== 1'b0 || start_game !== 1'b0) begin
            $display("FAIL: reset did not restore initial menu state");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: menu_ctrl stage navigation, display, config, confirm, reset");
        else
            $display("FAIL: menu_ctrl had %0d errors", errors);
        $finish;
    end
endmodule
