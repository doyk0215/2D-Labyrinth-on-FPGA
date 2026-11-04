`timescale 1ns / 1ps

// Story 4.2 stage selector and Story 4.3 rotation settings page. The display
// buffer stores ASCII bytes in status_text[8*k +: 8], with
// k = row*16 + column (top-left is byte 0). game_cfg is
// {custom, rot_speed_sel[1:0], restitution_sel[1:0], n_cells[4:0]}.
//
// Stage table:
//   0 EASY:   N=5 cells,  restitution_sel=0
//   1 MEDIUM: N=10 cells, restitution_sel=1
//   2 HARD:   N=15 cells, restitution_sel=1
//   3 EPIC:   N=20 cells, restitution_sel=1
//   4 CUSTOM: N=5+SW[3:0] (5..20), restitution_sel=0 at N=5, else 1
// Confirming CUSTOM with a size outside 5..20 starts nothing and shows an
// error page for ERROR_HOLD_CYCLES; the buttons are ignored meanwhile.
// Rotation presets are NORMAL=00, SLOW=01, FAST=10, TURBO=11.
module menu_ctrl #(
    parameter integer ERROR_HOLD_CYCLES = 200_000_000  // about 2 s at 100 MHz
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         return_to_menu,
    input  wire         menu_active,
    input  wire         btn_up,
    input  wire         btn_down,
    input  wire         btn_confirm,
    input  wire         btn_settings,
    input  wire [4:0]   custom_n,
    input  wire [47:0]  stage_high_scores_bcd,
    output reg          start_game,
    output reg  [9:0]   game_cfg,
    output reg  [511:0] status_text,
    output reg  [2:0]   selected_stage,
    output reg          settings_page,
    output wire         error_active
);

    localparam integer ERROR_W = (ERROR_HOLD_CYCLES > 1) ? $clog2(ERROR_HOLD_CYCLES + 1) : 1;

    reg [1:0] rot_speed_sel;
    reg [7:0] stage_cfg;
    // The error flag and the CUSTOM digits are registered so the counter and
    // the size formatting stay off the status-text path to the OLED mailbox.
    reg [ERROR_W-1:0] error_count;
    reg error_flag;
    reg [4:0] error_n;
    reg [15:0] custom_digits = "5 ";
    assign error_active = error_flag;
    wire custom_valid = (custom_n >= 5'd5) && (custom_n <= 5'd20);

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

    // 0..31 as one or two ASCII digits, left-aligned in two characters.
    function [15:0] size_ascii;
        input [4:0] value;
        reg [3:0] tens;
        begin
            tens = (value >= 5'd30) ? 4'd3 : (value >= 5'd20) ? 4'd2 :
                   (value >= 5'd10) ? 4'd1 : 4'd0;
            size_ascii = (tens != 0) ? {digit_ascii(tens), digit_ascii(value - 5'd10 * tens)}
                                     : {digit_ascii(value[3:0]), " "};
        end
    endfunction

    function [127:0] format_stage_high;
        input [103:0] prefix;
        input [11:0] score_bcd;
        begin
            if (score_bcd[11:8] != 0)
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[11:8]),
                    digit_ascii(score_bcd[7:4]),
                    digit_ascii(score_bcd[3:0])};
            else if (score_bcd[7:4] != 0)
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[7:4]),
                    digit_ascii(score_bcd[3:0]), " "};
            else
                format_stage_high = {prefix,
                    digit_ascii(score_bcd[3:0]), "  "};
        end
    endfunction

    reg [127:0] easy_high_line, medium_high_line, hard_high_line, epic_high_line, custom_line;
    always @* begin
        case (selected_stage)
            3'd1: stage_cfg = {1'b0, 2'b01, 5'd10};
            3'd2: stage_cfg = {1'b0, 2'b01, 5'd15};
            3'd3: stage_cfg = {1'b0, 2'b01, 5'd20};
            3'd4: stage_cfg = {1'b1, (custom_n <= 5'd5) ? 2'b00 : 2'b01, custom_n};
            default: stage_cfg = {1'b0, 2'b00, 5'd5};
        endcase

        game_cfg = {stage_cfg[7], rot_speed_sel, stage_cfg[6:0]};
        easy_high_line = format_stage_high((selected_stage == 3'd0) ? ">EASY   HIGH=" : " EASY   HIGH=",
                                           stage_high_scores_bcd[11:0]);
        medium_high_line = format_stage_high((selected_stage == 3'd1) ? ">MEDIUM HIGH=" : " MEDIUM HIGH=",
                                             stage_high_scores_bcd[23:12]);
        hard_high_line = format_stage_high((selected_stage == 3'd2) ? ">HARD   HIGH=" : " HARD   HIGH=",
                                           stage_high_scores_bcd[35:24]);
        epic_high_line = format_stage_high((selected_stage == 3'd3) ? ">EPIC   HIGH=" : " EPIC   HIGH=",
                                           stage_high_scores_bcd[47:36]);
        custom_line = {(selected_stage == 3'd4) ? ">CUSTOM 5+X=" : " CUSTOM 5+X=",
                       custom_digits, "  "};
        if (error_active) begin
            status_text = pack_text("CUSTOM SIZE     ",
                                    {"INVALID: N=", size_ascii(error_n), "   "},
                                    "USE 5-20 ON     ",
                                    "SW3-SW0         ");
        end else if (settings_page) begin
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
            if (selected_stage <= 3'd2)
                status_text = pack_text(easy_high_line, medium_high_line,
                                        hard_high_line, epic_high_line);
            else
                status_text = pack_text(medium_high_line, hard_high_line,
                                        epic_high_line, custom_line);
        end
    end

    always @(posedge clk) custom_digits <= size_ascii(custom_n);

    always @(posedge clk) begin
        if (rst) begin
            selected_stage <= 3'd0;
            rot_speed_sel <= 2'b00;
            settings_page <= 1'b0;
            start_game <= 1'b0;
            error_count <= {ERROR_W{1'b0}};
            error_flag <= 1'b0;
            error_n <= 5'd0;
        end else if (return_to_menu) begin
            // A gameplay reset returns to the stage list but keeps the
            // player's rotation preference for the next game.
            selected_stage <= 3'd0;
            settings_page <= 1'b0;
            start_game <= 1'b0;
            error_count <= {ERROR_W{1'b0}};
            error_flag <= 1'b0;
        end else begin
            start_game <= 1'b0;
            if (error_flag) begin
                // Held for ERROR_HOLD_CYCLES cycles: count down to zero, then clear.
                if (error_count == 0) error_flag <= 1'b0;
                else                  error_count <= error_count - 1'b1;
            end else if (menu_active) begin
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
                    selected_stage <= (selected_stage == 3'd0) ? 3'd4 : selected_stage - 1'b1;
                end else if (btn_down && !btn_up) begin
                    selected_stage <= (selected_stage == 3'd4) ? 3'd0 : selected_stage + 1'b1;
                end else if (btn_confirm) begin
                    if ((selected_stage == 3'd4) && !custom_valid) begin
                        error_count <= ERROR_HOLD_CYCLES - 1;
                        error_flag <= 1'b1;
                        error_n <= custom_n;
                    end else begin
                        start_game <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
