`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Selects and formats the single 4x16 ASCII status buffer consumed by the
// existing OLED mailbox. The OLED pixel driver remains unaware of game state.
module oled_status_text (
    input  wire [511:0] menu_text,
    input  wire [`GAME_STATE_W-1:0]   game_state,
    input  wire [7:0]   active_game_cfg,
    input  wire [7:0]   elapsed_minutes_bcd,
    input  wire [7:0]   elapsed_seconds_bcd,
    input wire [`ITEM_EFFECT_W-1:0] active_effect,
    input wire [6:0] effect_seconds,
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

    // Tens and units of the item seconds (Story 9.4): a 128-entry table instead
    // of /10 and %10, so the split is a LUT lookup, not a divider. Same digits
    // as /10 and %10 for every 7-bit value (100..127 give a tens digit of 10..12,
    // which digit_ascii shows as '?').
    function [7:0] seconds_digits;
        input [6:0] value;
        begin
            case (value)
                7'd0: seconds_digits = {4'd0, 4'd0};
                7'd1: seconds_digits = {4'd0, 4'd1};
                7'd2: seconds_digits = {4'd0, 4'd2};
                7'd3: seconds_digits = {4'd0, 4'd3};
                7'd4: seconds_digits = {4'd0, 4'd4};
                7'd5: seconds_digits = {4'd0, 4'd5};
                7'd6: seconds_digits = {4'd0, 4'd6};
                7'd7: seconds_digits = {4'd0, 4'd7};
                7'd8: seconds_digits = {4'd0, 4'd8};
                7'd9: seconds_digits = {4'd0, 4'd9};
                7'd10: seconds_digits = {4'd1, 4'd0};
                7'd11: seconds_digits = {4'd1, 4'd1};
                7'd12: seconds_digits = {4'd1, 4'd2};
                7'd13: seconds_digits = {4'd1, 4'd3};
                7'd14: seconds_digits = {4'd1, 4'd4};
                7'd15: seconds_digits = {4'd1, 4'd5};
                7'd16: seconds_digits = {4'd1, 4'd6};
                7'd17: seconds_digits = {4'd1, 4'd7};
                7'd18: seconds_digits = {4'd1, 4'd8};
                7'd19: seconds_digits = {4'd1, 4'd9};
                7'd20: seconds_digits = {4'd2, 4'd0};
                7'd21: seconds_digits = {4'd2, 4'd1};
                7'd22: seconds_digits = {4'd2, 4'd2};
                7'd23: seconds_digits = {4'd2, 4'd3};
                7'd24: seconds_digits = {4'd2, 4'd4};
                7'd25: seconds_digits = {4'd2, 4'd5};
                7'd26: seconds_digits = {4'd2, 4'd6};
                7'd27: seconds_digits = {4'd2, 4'd7};
                7'd28: seconds_digits = {4'd2, 4'd8};
                7'd29: seconds_digits = {4'd2, 4'd9};
                7'd30: seconds_digits = {4'd3, 4'd0};
                7'd31: seconds_digits = {4'd3, 4'd1};
                7'd32: seconds_digits = {4'd3, 4'd2};
                7'd33: seconds_digits = {4'd3, 4'd3};
                7'd34: seconds_digits = {4'd3, 4'd4};
                7'd35: seconds_digits = {4'd3, 4'd5};
                7'd36: seconds_digits = {4'd3, 4'd6};
                7'd37: seconds_digits = {4'd3, 4'd7};
                7'd38: seconds_digits = {4'd3, 4'd8};
                7'd39: seconds_digits = {4'd3, 4'd9};
                7'd40: seconds_digits = {4'd4, 4'd0};
                7'd41: seconds_digits = {4'd4, 4'd1};
                7'd42: seconds_digits = {4'd4, 4'd2};
                7'd43: seconds_digits = {4'd4, 4'd3};
                7'd44: seconds_digits = {4'd4, 4'd4};
                7'd45: seconds_digits = {4'd4, 4'd5};
                7'd46: seconds_digits = {4'd4, 4'd6};
                7'd47: seconds_digits = {4'd4, 4'd7};
                7'd48: seconds_digits = {4'd4, 4'd8};
                7'd49: seconds_digits = {4'd4, 4'd9};
                7'd50: seconds_digits = {4'd5, 4'd0};
                7'd51: seconds_digits = {4'd5, 4'd1};
                7'd52: seconds_digits = {4'd5, 4'd2};
                7'd53: seconds_digits = {4'd5, 4'd3};
                7'd54: seconds_digits = {4'd5, 4'd4};
                7'd55: seconds_digits = {4'd5, 4'd5};
                7'd56: seconds_digits = {4'd5, 4'd6};
                7'd57: seconds_digits = {4'd5, 4'd7};
                7'd58: seconds_digits = {4'd5, 4'd8};
                7'd59: seconds_digits = {4'd5, 4'd9};
                7'd60: seconds_digits = {4'd6, 4'd0};
                7'd61: seconds_digits = {4'd6, 4'd1};
                7'd62: seconds_digits = {4'd6, 4'd2};
                7'd63: seconds_digits = {4'd6, 4'd3};
                7'd64: seconds_digits = {4'd6, 4'd4};
                7'd65: seconds_digits = {4'd6, 4'd5};
                7'd66: seconds_digits = {4'd6, 4'd6};
                7'd67: seconds_digits = {4'd6, 4'd7};
                7'd68: seconds_digits = {4'd6, 4'd8};
                7'd69: seconds_digits = {4'd6, 4'd9};
                7'd70: seconds_digits = {4'd7, 4'd0};
                7'd71: seconds_digits = {4'd7, 4'd1};
                7'd72: seconds_digits = {4'd7, 4'd2};
                7'd73: seconds_digits = {4'd7, 4'd3};
                7'd74: seconds_digits = {4'd7, 4'd4};
                7'd75: seconds_digits = {4'd7, 4'd5};
                7'd76: seconds_digits = {4'd7, 4'd6};
                7'd77: seconds_digits = {4'd7, 4'd7};
                7'd78: seconds_digits = {4'd7, 4'd8};
                7'd79: seconds_digits = {4'd7, 4'd9};
                7'd80: seconds_digits = {4'd8, 4'd0};
                7'd81: seconds_digits = {4'd8, 4'd1};
                7'd82: seconds_digits = {4'd8, 4'd2};
                7'd83: seconds_digits = {4'd8, 4'd3};
                7'd84: seconds_digits = {4'd8, 4'd4};
                7'd85: seconds_digits = {4'd8, 4'd5};
                7'd86: seconds_digits = {4'd8, 4'd6};
                7'd87: seconds_digits = {4'd8, 4'd7};
                7'd88: seconds_digits = {4'd8, 4'd8};
                7'd89: seconds_digits = {4'd8, 4'd9};
                7'd90: seconds_digits = {4'd9, 4'd0};
                7'd91: seconds_digits = {4'd9, 4'd1};
                7'd92: seconds_digits = {4'd9, 4'd2};
                7'd93: seconds_digits = {4'd9, 4'd3};
                7'd94: seconds_digits = {4'd9, 4'd4};
                7'd95: seconds_digits = {4'd9, 4'd5};
                7'd96: seconds_digits = {4'd9, 4'd6};
                7'd97: seconds_digits = {4'd9, 4'd7};
                7'd98: seconds_digits = {4'd9, 4'd8};
                7'd99: seconds_digits = {4'd9, 4'd9};
                7'd100: seconds_digits = {4'd10, 4'd0};
                7'd101: seconds_digits = {4'd10, 4'd1};
                7'd102: seconds_digits = {4'd10, 4'd2};
                7'd103: seconds_digits = {4'd10, 4'd3};
                7'd104: seconds_digits = {4'd10, 4'd4};
                7'd105: seconds_digits = {4'd10, 4'd5};
                7'd106: seconds_digits = {4'd10, 4'd6};
                7'd107: seconds_digits = {4'd10, 4'd7};
                7'd108: seconds_digits = {4'd10, 4'd8};
                7'd109: seconds_digits = {4'd10, 4'd9};
                7'd110: seconds_digits = {4'd11, 4'd0};
                7'd111: seconds_digits = {4'd11, 4'd1};
                7'd112: seconds_digits = {4'd11, 4'd2};
                7'd113: seconds_digits = {4'd11, 4'd3};
                7'd114: seconds_digits = {4'd11, 4'd4};
                7'd115: seconds_digits = {4'd11, 4'd5};
                7'd116: seconds_digits = {4'd11, 4'd6};
                7'd117: seconds_digits = {4'd11, 4'd7};
                7'd118: seconds_digits = {4'd11, 4'd8};
                7'd119: seconds_digits = {4'd11, 4'd9};
                7'd120: seconds_digits = {4'd12, 4'd0};
                7'd121: seconds_digits = {4'd12, 4'd1};
                7'd122: seconds_digits = {4'd12, 4'd2};
                7'd123: seconds_digits = {4'd12, 4'd3};
                7'd124: seconds_digits = {4'd12, 4'd4};
                7'd125: seconds_digits = {4'd12, 4'd5};
                7'd126: seconds_digits = {4'd12, 4'd6};
                7'd127: seconds_digits = {4'd12, 4'd7};
                default: seconds_digits = 8'h00;
            endcase
        end
    endfunction


    reg [63:0] item_name;
    wire [7:0] effect_digits = seconds_digits(effect_seconds);
    reg [127:0] play_line;
    reg [127:0] stage_text;
    always @* begin
        case(active_effect)
            `ITEM_LOW_GRAV: item_name="LOW GRAV";
            `ITEM_INVINCIBLE: item_name="INVINCIB";
            `ITEM_TIME_BONUS: item_name="TIME +  ";
            `ITEM_REVERSE_GRAV: item_name="REV GRAV";
            `ITEM_HIGH_GRAV: item_name="HI GRAV ";
            `ITEM_ZERO_GRAV: item_name="ZERO G  ";
            `ITEM_INVERT: item_name="INVERT  ";
            `ITEM_FOG: item_name="FOG     ";
            default: item_name="        ";
        endcase
        play_line="PLAYING         ";
        if(active_effect < `ITEM_NONE && active_effect <= `ITEM_FOG && effect_seconds != 0)
            play_line={"ITEM:",item_name," ",digit_ascii(effect_digits[7:4]),digit_ascii(effect_digits[3:0])};
        case (active_game_cfg[3:0])
            4'd5:    stage_text = "STAGE 1 EASY    ";
            4'd10:   stage_text = "STAGE 2 HARD    ";
            4'd15:   stage_text = "STAGE 3 HUGE    ";
            default: stage_text = "STAGE ?         ";
        endcase

        case (game_state)
            `ST_MENU: status_text = menu_text;
            `ST_GENERATE: status_text = pack_text(
                stage_text, "TIME 00:00      ",
                "GENERATING...   ", "PLEASE WAIT     "
            );
            `ST_PLAY: status_text = pack_text(
                stage_text, format_time(elapsed_minutes_bcd,
                                        elapsed_seconds_bcd),
                play_line, "BTNC RESET      "
            );
            `ST_WIN: status_text = pack_text(
                stage_text, format_time(elapsed_minutes_bcd,
                                        elapsed_seconds_bcd),
                "YOU WIN         ", "AUTO REPLAY     "
            );
            `ST_LOSE: status_text = pack_text(
                stage_text, "TIME 00:00      ",
                "TIME UP         ", "BACK TO MENU    "
            );
            default: status_text = menu_text;
        endcase
    end
endmodule
