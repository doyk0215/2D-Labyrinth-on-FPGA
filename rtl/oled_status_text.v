`timescale 1ns / 1ps

// Selects and formats the single 4x16 ASCII status buffer consumed by the
// existing OLED mailbox. The OLED pixel driver remains unaware of game state.
module oled_status_text (
    input  wire [511:0] menu_text,
    input  wire [1:0]   game_state,
    input  wire [7:0]   active_game_cfg,
    input  wire [7:0]   elapsed_minutes_bcd,
    input  wire [7:0]   elapsed_seconds_bcd,
    output reg  [511:0] status_text
);
    localparam [1:0] MENU     = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY     = 2'b10;
    localparam [1:0] WIN      = 2'b11;

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

    function [127:0] format_time;
        input [7:0] minutes_bcd;
        input [7:0] seconds_bcd;
        begin
            format_time = {
                "TIME ",
                digit_ascii(minutes_bcd[7:4]),
                digit_ascii(minutes_bcd[3:0]),
                ":",
                digit_ascii(seconds_bcd[7:4]),
                digit_ascii(seconds_bcd[3:0]),
                "      "
            };
        end
    endfunction

    reg [127:0] stage_text;
    always @* begin
        case (active_game_cfg[3:0])
            4'd5:    stage_text = "STAGE 1 EASY    ";
            4'd10:   stage_text = "STAGE 2 HARD    ";
            default: stage_text = "STAGE ?         ";
        endcase

        case (game_state)
            MENU: status_text = menu_text;
            GENERATE: status_text = pack_text(
                stage_text, "TIME 00:00      ",
                "GENERATING...   ", "PLEASE WAIT     "
            );
            PLAY: status_text = pack_text(
                stage_text, format_time(elapsed_minutes_bcd,
                                        elapsed_seconds_bcd),
                "PLAYING         ", "BTNC RESET      "
            );
            WIN: status_text = pack_text(
                stage_text, format_time(elapsed_minutes_bcd,
                                        elapsed_seconds_bcd),
                "YOU WIN         ", "AUTO REPLAY     "
            );
            default: status_text = menu_text;
        endcase
    end
endmodule
