`timescale 1ns / 1ps

// Fixed screen-space WIN panel and green outline for Stories 3.3 and 8.1.
// The panel shows "YOU WIN" and, below it, "TIME mm:ss" from the BCD inputs.
// Outputs share render's one-clock pixel latency. The renderer decides when
// to show them from its frame snapshot of game_state; the maze stays behind.
module win_overlay (
    input  wire       clk,
    input  wire       rst,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active_video,
    input  wire [7:0] time_min_bcd,
    input  wire [7:0] time_sec_bcd,
    output reg        panel_on,
    output reg        accent_on,
    output wire       text_on
);
    // Title: 5x7 characters at 8x scale, one blank column between characters.
    // "YOU WIN" spans x=156..483, y=212..267, centred on the VGA picture.
    wire [9:0] text_x = pixel_x - 10'd156;
    wire [9:0] text_y = pixel_y - 10'd212;
    wire [5:0] text_col = text_x[8:3];
    reg [6:0] title_ch;
    reg [2:0] title_col;
    always @* begin
        title_ch = 7'h20;
        title_col = 3'd0;
        if (text_col < 6'd5) begin
            title_ch = "Y"; title_col = text_col;
        end else if (text_col >= 6'd6 && text_col < 6'd11) begin
            title_ch = "O"; title_col = text_col - 6'd6;
        end else if (text_col >= 6'd12 && text_col < 6'd17) begin
            title_ch = "U"; title_col = text_col - 6'd12;
        end else if (text_col >= 6'd24 && text_col < 6'd29) begin
            title_ch = "W"; title_col = text_col - 6'd24;
        end else if (text_col >= 6'd30 && text_col < 6'd35) begin
            title_ch = "I"; title_col = text_col - 6'd30;
        end else if (text_col >= 6'd36 && text_col < 6'd41) begin
            title_ch = "N"; title_col = text_col - 6'd36;
        end
    end

    // Time line: 5x7 characters at 4x scale in ten 32 px cells
    // T I M E _ m m : s s, spanning x=160..479, y=284..311.
    wire [9:0] time_x = pixel_x - 10'd160;
    wire [9:0] time_y = pixel_y - 10'd284;
    wire [3:0] time_cell = time_x[8:5];
    wire [2:0] time_glyph_col = time_x[4:2];
    reg [6:0] time_ch;
    always @* begin
        case (time_cell)
            4'd0: time_ch = "T";
            4'd1: time_ch = "I";
            4'd2: time_ch = "M";
            4'd3: time_ch = "E";
            4'd5: time_ch = {3'b011, time_min_bcd[7:4]};
            4'd6: time_ch = {3'b011, time_min_bcd[3:0]};
            4'd7: time_ch = ":";
            4'd8: time_ch = {3'b011, time_sec_bcd[7:4]};
            4'd9: time_ch = {3'b011, time_sec_bcd[3:0]};
            default: time_ch = 7'h20;
        endcase
        if (time_glyph_col >= 3'd5) time_ch = 7'h20;
    end

    // The title band ends above y=284 and the time band starts there, so the
    // rows never overlap and one font ROM serves both.
    wire time_sel = pixel_y >= 10'd276;
    wire [6:0] ch = time_sel ? time_ch : title_ch;
    wire [2:0] font_col = time_sel ? time_glyph_col : title_col;
    wire [2:0] row_now = time_sel ? time_y[4:2] : text_y[5:3];

    wire [7:0] font_data;
    font_rom font_i (.clk(clk), .ch(ch), .col(font_col), .data(font_data));
    reg text_area_d;
    reg [2:0] text_row_d;
    assign text_on = text_area_d && font_data[text_row_d];

    wire panel_now = pixel_x >= 10'd132 && pixel_x < 10'd508 &&
                     pixel_y >= 10'd192 && pixel_y < 10'd324;
    wire panel_rim = panel_now && (pixel_x < 10'd136 || pixel_x >= 10'd504 ||
                                   pixel_y < 10'd196 || pixel_y >= 10'd320);
    wire screen_rim = pixel_x >= 10'd12 && pixel_x < 10'd628 &&
                      pixel_y >= 10'd12 && pixel_y < 10'd468 &&
                      (pixel_x < 10'd16 || pixel_x >= 10'd624 ||
                       pixel_y < 10'd16 || pixel_y >= 10'd464);
    wire title_area_now = pixel_x >= 10'd156 && pixel_x < 10'd484 &&
                          pixel_y >= 10'd212 && pixel_y < 10'd268;
    wire time_area_now = pixel_x >= 10'd160 && pixel_x < 10'd480 &&
                         pixel_y >= 10'd284 && pixel_y < 10'd312;
    always @(posedge clk) begin
        if (rst) begin
            panel_on <= 1'b0;
            accent_on <= 1'b0;
            text_area_d <= 1'b0;
            text_row_d <= 3'd0;
        end else begin
            panel_on <= active_video && panel_now;
            accent_on <= active_video && (screen_rim || panel_rim);
            text_area_d <= active_video && (title_area_now || time_area_now);
            text_row_d <= row_now;
        end
    end
endmodule
