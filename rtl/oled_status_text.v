`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Selects and formats the single 4x16 ASCII status buffer consumed by the
// existing OLED mailbox. The OLED pixel driver remains unaware of game state.
module oled_status_text (
    input  wire [511:0] menu_text,
    input  wire         instructions_active,
    input  wire [2:0]   instructions_scroll,
    input  wire [`GAME_STATE_W-1:0]   game_state,
    input  wire [7:0]   active_game_cfg,
    input  wire [7:0]   elapsed_minutes_bcd,
    input  wire [7:0]   elapsed_seconds_bcd,
    input wire [`ITEM_EFFECT_W-1:0] active_effect,
    input wire [6:0] effect_seconds,
    input wire [11:0] levels_completed_bcd,
    input wire [1:0] pause_selection,
    output reg  [511:0] status_text
);

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
        begin
            digit_ascii = (digit <= 4'd9) ? (8'h30 + digit) : 8'h3F;
        end
    endfunction

    reg [127:0] stage_text;
    reg [127:0] completed_count_line;
    reg [127:0] pause_resume_line, pause_restart_line, pause_menu_line;
    reg [127:0] instruction_line_0, instruction_line_1, instruction_line_2;
    reg [127:0] instruction_header;
    always @* begin
        case (active_game_cfg[3:0])
            4'd5:    stage_text = "STAGE 1 EASY    ";
            4'd10:   stage_text = "STAGE 2 HARD    ";
            4'd15:   stage_text = "STAGE 3 HUGE    ";
            default: stage_text = "STAGE ?         ";
        endcase
        completed_count_line = {"N: ",
            digit_ascii(levels_completed_bcd[11:8]),
            digit_ascii(levels_completed_bcd[7:4]),
            digit_ascii(levels_completed_bcd[3:0]),
            "          "};
        pause_resume_line = (pause_selection == 2'd0) ? ">RESUME         " : " RESUME         ";
        pause_restart_line = (pause_selection == 2'd1) ? ">RESTART        " : " RESTART        ";
        pause_menu_line = (pause_selection == 2'd2) ? ">MENU           " : " MENU           ";

        case (instructions_scroll)
            3'd1: instruction_header = "INSTRUCTIONS 2/4";
            3'd2: instruction_header = "INSTRUCTIONS 3/4";
            3'd3: instruction_header = "INSTRUCTIONS 4/4";
            default: instruction_header = "INSTRUCTIONS 1/4";
        endcase
        case (instructions_scroll)
            3'd1: begin instruction_line_0="RMB/BTN R: CW   "; instruction_line_1="SW0: 90 DEG SNAP"; instruction_line_2="BTNU: PAUSE     "; end
            3'd2: begin instruction_line_0="SW0: 90 DEG SNAP"; instruction_line_1="BTNU: PAUSE     "; instruction_line_2="BTND: RESET POS "; end
            3'd3: begin instruction_line_0="BTNU: PAUSE     "; instruction_line_1="BTND: RESET POS "; instruction_line_2="BTNC: MAIN MENU "; end
            default: begin instruction_line_0="LMB/BTN L: CCW  "; instruction_line_1="RMB/BTN R: CW   "; instruction_line_2="SW0: 90 DEG SNAP"; end
        endcase

        case (game_state)
            `ST_MENU: begin
                case (instructions_active)
                    1'b1: status_text = pack_text(instruction_header,
                        instruction_line_0, instruction_line_1, instruction_line_2);
                    default: status_text = menu_text;
                endcase
            end
            `ST_GENERATE: status_text = pack_text(
                stage_text, "LEVELS COMPLETED", completed_count_line,
                "GENERATING...   "
            );
            `ST_PLAY: status_text = pack_text(
                stage_text, "LEVELS COMPLETED", completed_count_line,
                "BTNC RESET      "
            );
            `ST_PAUSED: status_text = pack_text(
                "PAUSED          ", pause_resume_line, pause_restart_line,
                pause_menu_line
            );
            `ST_WIN: status_text = pack_text(
                stage_text, "LEVELS COMPLETED", completed_count_line,
                "YOU WIN         "
            );
            `ST_LOSE: status_text = pack_text(
                stage_text, "LEVELS COMPLETED", completed_count_line,
                "TIME UP         "
            );
            default: status_text = menu_text;
        endcase
    end
endmodule
