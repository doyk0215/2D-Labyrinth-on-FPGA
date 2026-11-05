`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Screen-space status panel for the upper-right corner of the VGA image.
// The first row shows time remaining; the second shows the current effect and
// its seconds remaining. Coordinates and font flags share one clock of latency
// with render's VGA output.
module game_status_hud #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BONUS_SECONDS = 10,
    parameter integer BONUS_NOTICE_MS = 2000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       phys_init,
    input  wire       time_bonus_pulse,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active_video,
    input  wire [`GAME_STATE_W-1:0] game_state,
    input  wire [`N_CELLS_W-1:0] n_cells,
    input  wire [7:0] minutes_bcd,
    input  wire [7:0] seconds_bcd,
    input  wire       warning_active,
    input  wire       timer_flash_red,
    input  wire [`ITEM_EFFECT_W-1:0] active_effect,
    input  wire [6:0] effect_seconds,
    output reg        panel_on,
    output reg        accent_on,
    output wire       text_on,
    output reg        timer_line,
    output reg        timer_red,
    output reg        item_line,
    output reg        debuff_line,
    output reg        bonus_line
);
    // This is a display receipt for an already-applied instant bonus. It
    // never drives the game timer or replaces the current timed effect.
    localparam integer BONUS_VALUE = BONUS_SECONDS < 0 ? 0 :
                                     BONUS_SECONDS > 5999 ? 5999 : BONUS_SECONDS;
    localparam [63:0] NOTICE_RAW = 64'd1 * ((CLK_HZ > 0) ? CLK_HZ : 1) *
                                  ((BONUS_NOTICE_MS > 0) ? BONUS_NOTICE_MS : 0) / 1000;
    localparam [63:0] NOTICE_CYCLES = NOTICE_RAW > 0 ? NOTICE_RAW : 1;
    localparam integer NOTICE_W = $clog2(NOTICE_CYCLES + 1);
    reg [NOTICE_W-1:0] notice_left = 0;
    reg bonus_notice = 0;
    always @(posedge clk) begin
        if (rst || phys_init || (game_state != `ST_PLAY && game_state != `ST_PAUSED)) begin
            notice_left <= 0;
            bonus_notice <= 0;
        end else begin
            if (game_state == `ST_PLAY) begin
                if (time_bonus_pulse && BONUS_VALUE != 0)
                    notice_left <= NOTICE_CYCLES;
                else if (notice_left != 0)
                    notice_left <= notice_left - 1'b1;
            end
            // Keep the row's contents/colour stable for the visible frame.
            if (frame_tick)
                bonus_notice <= notice_left != 0 ||
                                (game_state == `ST_PLAY && time_bonus_pulse && BONUS_VALUE != 0);
        end
    end
    function [7:0] digit_ascii;
        input [3:0] digit;
        begin digit_ascii = (digit <= 4'd9) ? (8'h30 + digit) : 8'h3f; end
    endfunction

    // Return two ASCII digits. Keeping both bytes is important for durations
    // above nine seconds (for example, 12 must not truncate to just "2").
    function [15:0] seconds_digits;
        input [6:0] value;
        reg [6:0] tens;
        reg [6:0] ones;
        begin
            tens = value / 10;
            ones = value - (tens * 10);
            seconds_digits = {digit_ascii(tens[3:0]), digit_ascii(ones[3:0])};
        end
    endfunction

    wire effect_active = active_effect != `ITEM_NONE &&
                         active_effect <= `ITEM_FOG &&
                         active_effect != `ITEM_TIME_BONUS &&
                         effect_seconds != 0;
    wire effect_debuff = active_effect >= `ITEM_REVERSE_GRAV &&
                         active_effect <= `ITEM_FOG;
    reg [63:0] item_name;
    reg [159:0] time_line;
    reg [159:0] item_status_line;
    wire [15:0] effect_digits = seconds_digits(effect_seconds);
    // Parameter arithmetic is elaboration-only, including unusually large
    // bonuses; normal +10 seconds is shown as TIME +10s.
    localparam [7:0] BONUS_TENS = 8'h30 + ((BONUS_VALUE / 10) % 10);
    localparam [7:0] BONUS_ONES = 8'h30 + (BONUS_VALUE % 10);
    localparam [7:0] BONUS_MT = 8'h30 + (BONUS_VALUE / 600);
    localparam [7:0] BONUS_MO = 8'h30 + ((BONUS_VALUE / 60) % 10);
    localparam [7:0] BONUS_ST = 8'h30 + ((BONUS_VALUE % 60) / 10);
    localparam [159:0] BONUS_TEXT = BONUS_VALUE >= 100 ?
        {"TIME +", BONUS_MT, BONUS_MO, ":", BONUS_ST, BONUS_ONES, {9{8'h20}}} :
        BONUS_VALUE >= 10 ? {"TIME +", BONUS_TENS, BONUS_ONES, "s", {11{8'h20}}} :
                           {"TIME +", BONUS_ONES, "s", {12{8'h20}}};

    always @* begin
        case (active_effect)
            `ITEM_LOW_GRAV:     item_name = "LOW GRAV";
            `ITEM_INVINCIBLE:   item_name = "INVINCIB";
            `ITEM_REVERSE_GRAV: item_name = "REV GRAV";
            `ITEM_HIGH_GRAV:    item_name = "HI GRAV ";
            `ITEM_ZERO_GRAV:    item_name = "ZERO G  ";
            `ITEM_INVERT:       item_name = "INVERT  ";
            `ITEM_FOG:          item_name = "FOG     ";
            default:            item_name = "        ";
        endcase

        time_line = {"TIME ",
                     digit_ascii(minutes_bcd[7:4]),
                     digit_ascii(minutes_bcd[3:0]), ":",
                     digit_ascii(seconds_bcd[7:4]),
                     digit_ascii(seconds_bcd[3:0]),
                     {10{8'h20}}};
        if (bonus_notice)
            item_status_line = BONUS_TEXT;
        else if (effect_active && effect_debuff)
            item_status_line = {"DEBUFF ", item_name, " ", effect_digits, "s", 8'h20};
        else if (effect_active)
            item_status_line = {"BUFF ", item_name, " ", effect_digits, "s", {3{8'h20}}};
        else
            item_status_line = {"ITEM NONE", {11{8'h20}}};
    end

    // Panel: x=380..627, y=12..59. Each 20-character row uses a 12-pixel
    // cell (10x14 glyph plus a 2-pixel gap) with four-pixel side margins.
    // Maps up to N = 5 (EASY and small custom sizes) still show the timer, but
    // omit the item row because they have no buff/debuff boxes.
    wire play_active = (game_state == `ST_PLAY);
    wire item_row_active = (n_cells > 5'd5);
    wire panel_now = pixel_x >= 10'd380 && pixel_x < 10'd628 &&
                     pixel_y >= 10'd12 && pixel_y < 10'd60;
    wire accent_now = panel_now && (pixel_x < 10'd384 || pixel_x >= 10'd624 ||
                                    pixel_y < 10'd16 || pixel_y >= 10'd56);
    wire [9:0] text_x = pixel_x - 10'd384;
    wire [4:0] text_cell = text_x / 10'd12;
    wire [3:0] text_cell_x = text_x - (text_cell * 10'd12);
    wire row0_now = pixel_y >= 10'd18 && pixel_y < 10'd32;
    wire row1_now = pixel_y >= 10'd38 && pixel_y < 10'd52;
    wire [9:0] text_row_y = row0_now ? (pixel_y - 10'd18) : (pixel_y - 10'd38);
    wire text_pixel_now = active_video && play_active &&
                          pixel_x >= 10'd384 && pixel_x < 10'd624 &&
                          (row0_now || (row1_now && item_row_active)) &&
                          text_cell < 10'd20 &&
                          text_cell_x < 4'd10;

    reg [7:0] character_now;
    always @* begin
        if (row0_now)
            character_now = time_line[159 - (text_cell * 8) -: 8];
        else
            character_now = item_status_line[159 - (text_cell * 8) -: 8];
    end

    wire [7:0] font_data;
    font_rom font_i (
        .clk(clk), .ch(character_now[6:0]),
        .col(text_cell_x[3:1]), .data(font_data)
    );
    reg text_area_d;
    reg [2:0] text_row_d;
    always @(posedge clk) begin
        if (rst) begin
            panel_on <= 1'b0;
            accent_on <= 1'b0;
            text_area_d <= 1'b0;
            text_row_d <= 3'd0;
            timer_line <= 1'b0;
            timer_red <= 1'b0;
            item_line <= 1'b0;
            debuff_line <= 1'b0;
            bonus_line <= 1'b0;
        end else begin
            panel_on <= active_video && play_active && panel_now;
            accent_on <= active_video && play_active && accent_now;
            text_area_d <= text_pixel_now;
            text_row_d <= text_row_y[3:1];
            timer_line <= text_pixel_now && row0_now;
            timer_red <= text_pixel_now && row0_now && warning_active && timer_flash_red;
            item_line <= text_pixel_now && row1_now;
            debuff_line <= text_pixel_now && row1_now && !bonus_notice && effect_active && effect_debuff;
            bonus_line <= text_pixel_now && row1_now && bonus_notice;
        end
    end
    assign text_on = text_area_d && font_data[text_row_d];
endmodule
