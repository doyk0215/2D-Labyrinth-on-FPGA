`timescale 1ns / 1ps

// Story 4.2 stage selector and Story 4.3 rotation settings page. The display
// buffer stores ASCII bytes in status_text[8*k +: 8], with
// k = row*16 + column (top-left is byte 0). game_cfg is
// {rot_speed_sel[1:0], restitution_sel[1:0], n_cells[3:0]}.
//
// Stage table:
//   0 EASY: N=5 cells, restitution_sel=0
//   1 HARD: N=10 cells, restitution_sel=1
//   2 HUGE: N=15 cells, restitution_sel=1 (same bounce preset as HARD)
// Rotation presets are NORMAL=00, SLOW=01, FAST=10, TURBO=11.
module menu_ctrl (
    input  wire         clk,
    input  wire         rst,
    input  wire         return_to_menu,
    input  wire         menu_active,
    input  wire         btn_up,
    input  wire         btn_down,
    input  wire         btn_confirm,
    input  wire         btn_settings,
    input  wire [35:0]  stage_high_scores_bcd,
    output reg          start_game,
    output reg  [7:0]   game_cfg,
    output reg  [511:0] status_text,
    output reg  [1:0]   selected_stage,
    output reg          settings_page
);

    reg [1:0] rot_speed_sel;
    reg [5:0] stage_cfg;

    function [1:0] speed_up;
        input [1:0] speed;
        begin
            case (speed)
                2'b01: speed_up = 2'b00; // SLOW -> NORMAL
                2'b00: speed_up = 2'b10; // NORMAL -> FAST
                2'b10: speed_up = 2'b11; // FAST -> TURBO
                default: speed_up = 2'b01; // TURBO -> SLOW
            endcase
        end
    endfunction

    function [1:0] speed_down;
        input [1:0] speed;
        begin
            case (speed)
                2'b01: speed_down = 2'b11; // SLOW -> TURBO
                2'b00: speed_down = 2'b01; // NORMAL -> SLOW
                2'b10: speed_down = 2'b00; // FAST -> NORMAL
                default: speed_down = 2'b10; // TURBO -> FAST
            endcase
        end
    endfunction

    function [511:0] pack_text;
        input [127:0] r0;
        input [127:0] r1;
        input [127:0] r2;
        input [127:0] r3;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                pack_text[8 * i        +: 8] = r0[127 - 8 * i -: 8];
                pack_text[8 * (16 + i) +: 8] = r1[127 - 8 * i -: 8];
                pack_text[8 * (32 + i) +: 8] = r2[127 - 8 * i -: 8];
                pack_text[8 * (48 + i) +: 8] = r3[127 - 8 * i -: 8];
            end
        end
    endfunction

    function [7:0] digit_ascii;
        input [3:0] digit;
        begin digit_ascii = (digit <= 4'd9) ? (8'h30 + digit) : 8'h3f; end
    endfunction

    function [127:0] format_stage_high;
        input [87:0] prefix;
        input [11:0] score_bcd;
        begin
            if (score_bcd[11:8] != 0)
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[11:8]),
                    digit_ascii(score_bcd[7:4]),
                    digit_ascii(score_bcd[3:0]), "  "};
            else if (score_bcd[7:4] != 0)
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[7:4]),
                    digit_ascii(score_bcd[3:0]), "   "};
            else
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[3:0]), "    "};
        end
    endfunction

    reg [127:0] easy_high_line, hard_high_line, huge_high_line;
    always @* begin
        case (selected_stage)
            2'd1: stage_cfg = {2'b01, 4'd10};
            2'd2: stage_cfg = {2'b01, 4'd15};
            default: stage_cfg = {2'b00, 4'd5};
        endcase

        game_cfg = {rot_speed_sel, stage_cfg};
        easy_high_line = format_stage_high((selected_stage == 2'd0) ? ">EASY HIGH=" : " EASY HIGH=",
                                           stage_high_scores_bcd[11:0]);
        hard_high_line = format_stage_high((selected_stage == 2'd1) ? ">HARD HIGH=" : " HARD HIGH=",
                                           stage_high_scores_bcd[23:12]);
        huge_high_line = format_stage_high((selected_stage == 2'd2) ? ">HUGE HIGH=" : " HUGE HIGH=",
                                           stage_high_scores_bcd[35:24]);
        if (settings_page) begin
            case (rot_speed_sel)
                2'b01: status_text = pack_text("ROTATION SPEED  ",
                                               "SPEED:SLOW 45   ",
                                               "UP/DN CHG RATE  ",
                                               "BTNC BACK       ");
                2'b10: status_text = pack_text("ROTATION SPEED  ",
                                               "SPEED:FAST 135  ",
                                               "UP/DN CHG RATE  ",
                                               "BTNC BACK       ");
                2'b11: status_text = pack_text("ROTATION SPEED  ",
                                               "SPEED:TURBO 180 ",
                                               "UP/DN CHG RATE  ",
                                               "BTNC BACK       ");
                default: status_text = pack_text("ROTATION SPEED  ",
                                                 "SPEED:NORMAL 90 ",
                                                 "UP/DN CHG RATE  ",
                                                 "BTNC BACK       ");
            endcase
        end else begin
            status_text = pack_text("L=SET C=GO      ",
                                    easy_high_line,
                                    hard_high_line,
                                    huge_high_line);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            selected_stage <= 2'd0;
            rot_speed_sel <= 2'b00;
            settings_page <= 1'b0;
            start_game <= 1'b0;
        end else if (return_to_menu) begin
            // A gameplay reset returns to the stage list but keeps the
            // player's rotation preference for the next game.
            selected_stage <= 2'd0;
            settings_page <= 1'b0;
            start_game <= 1'b0;
        end else begin
            start_game <= 1'b0;
            if (menu_active) begin
                if (settings_page) begin
                    if (btn_confirm) begin
                        settings_page <= 1'b0;
                    end else if (btn_up && !btn_down) begin
                        rot_speed_sel <= speed_up(rot_speed_sel);
                    end else if (btn_down && !btn_up) begin
                        rot_speed_sel <= speed_down(rot_speed_sel);
                    end
                end else if (btn_settings) begin
                    settings_page <= 1'b1;
                end else if (btn_up && !btn_down) begin
                    selected_stage <= (selected_stage == 2'd0) ? 2'd2 : selected_stage - 1'b1;
                end else if (btn_down && !btn_up) begin
                    selected_stage <= (selected_stage >= 2'd2) ? 2'd0 : selected_stage + 1'b1;
                end else if (btn_confirm) begin
                    start_game <= 1'b1;
                end
            end
        end
    end

endmodule
