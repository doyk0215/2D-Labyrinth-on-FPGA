`timescale 1ns / 1ps

// Screen-space menu panel shared by welcome, settings, and instructions.
// The underlying N=20 maze remains visible around the translucent-style
// framing panel; output timing matches the renderer's one-clock pixel path.
module monitor_menu_overlay (
    input  wire       clk,
    input  wire       rst,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active_video,
    input  wire [1:0] mode,       // 0 welcome, 1 settings, 2 instructions
    output reg        panel_on,
    output reg        accent_on,
    output wire       text_on
);
    localparam [327:0] LINE_WELCOME = "L = SETTINGS  C = START  R = INSTRUCTIONS";
    localparam [143:0] LINE_WELCOME_SECOND = "U/D = SELECT STAGE";
    localparam [287:0] LINE_SETTINGS = "U/D = CHANGE ROTATION RATE  C = BACK";
    localparam [239:0] LINE_INSTRUCTIONS = "U/D = SCROLL UP/DOWN  C = BACK";

    reg [511:0] subtitle_line;
    reg [4:0] title_len;
    reg [5:0] subtitle_len;
    reg [9:0] title_x;
    reg [9:0] subtitle_x;
    always @* begin
        case (mode)
            2'd1: begin
                title_len = 5'd8;
                title_x = 10'd128;
                subtitle_line = LINE_SETTINGS;
                subtitle_len = 6'd36;
                subtitle_x = 10'd104;
            end
            2'd2: begin
                title_len = 5'd12;
                title_x = 10'd32;
                subtitle_line = LINE_INSTRUCTIONS;
                subtitle_len = 6'd30;
                subtitle_x = 10'd140;
            end
            default: begin
                title_len = 5'd7;
                title_x = 10'd152;
                subtitle_line = LINE_WELCOME;
                subtitle_len = 6'd41;
                subtitle_x = 10'd74;
            end
        endcase
    end

    wire [9:0] title_dx = pixel_x - title_x;
    wire [9:0] title_dy = pixel_y - 10'd180;
    wire [6:0] title_column = pixel_x[9:3] - title_x[9:3];
    wire [4:0] title_cell = title_column / 7'd6;
    wire [2:0] title_col = title_column - (title_cell * 5'd6);
    wire [9:0] subtitle_dx = pixel_x - subtitle_x;
    wire [9:0] subtitle_dy = pixel_y - 10'd296;
    wire [5:0] subtitle_cell = subtitle_dx / 10'd12;
    wire [2:0] subtitle_col = (subtitle_dx % 10'd12) >> 1;
    wire [9:0] subtitle2_dx = pixel_x - 10'd212;
    wire [5:0] subtitle2_cell = subtitle2_dx / 10'd12;
    wire [2:0] subtitle2_col = (subtitle2_dx % 10'd12) >> 1;

    reg [6:0] ch;
    reg [2:0] font_col;
    reg [2:0] font_row;
    reg text_area;
    always @* begin
        ch = 7'h20;
        font_col = 3'd0;
        font_row = 3'd0;
        text_area = 1'b0;
        if ((pixel_y >= 10'd180) && (pixel_y < 10'd236) &&
            (pixel_x >= title_x) && (title_cell < title_len)) begin
            ch = title_character(mode, title_cell);
            font_col = title_col;
            font_row = title_dy[5:3];
            text_area = 1'b1;
        end else if ((pixel_y >= 10'd296) && (pixel_y < 10'd310) &&
                     (pixel_x >= subtitle_x) && (subtitle_cell < subtitle_len)) begin
            ch = subtitle_line[(subtitle_len - 1'b1 - subtitle_cell) * 8 +: 7];
            font_col = subtitle_col;
            font_row = subtitle_dy[3:1];
            text_area = (subtitle_col < 3'd5);
        end else if ((mode == 2'd0) && (pixel_y >= 10'd322) &&
                     (pixel_y < 10'd336) && (pixel_x >= 10'd212) &&
                     (subtitle2_cell < 6'd18)) begin
            ch = LINE_WELCOME_SECOND[(6'd17 - subtitle2_cell) * 8 +: 7];
            font_col = subtitle2_col;
            font_row = (pixel_y - 10'd322) >> 1;
            text_area = (subtitle2_col < 3'd5);
        end
    end

    // Select title characters with a small case decoder. Packed-string
    // variable part-selects created a long pixel-to-font-ROM address path.
    function [6:0] title_character;
        input [1:0] page;
        input [4:0] index;
        begin
            title_character = 7'h20;
            case (page)
                2'd1: case (index)
                    5'd0: title_character="S"; 5'd1: title_character="E";
                    5'd2: title_character="T"; 5'd3: title_character="T";
                    5'd4: title_character="I"; 5'd5: title_character="N";
                    5'd6: title_character="G"; 5'd7: title_character="S";
                    default: title_character=7'h20;
                endcase
                2'd2: case (index)
                    5'd0: title_character="I";  5'd1: title_character="N";
                    5'd2: title_character="S";  5'd3: title_character="T";
                    5'd4: title_character="R";  5'd5: title_character="U";
                    5'd6: title_character="C";  5'd7: title_character="T";
                    5'd8: title_character="I";  5'd9: title_character="O";
                    5'd10: title_character="N"; 5'd11: title_character="S";
                    default: title_character=7'h20;
                endcase
                default: case (index)
                    5'd0: title_character="W"; 5'd1: title_character="E";
                    5'd2: title_character="L"; 5'd3: title_character="C";
                    5'd4: title_character="O"; 5'd5: title_character="M";
                    5'd6: title_character="E";
                    default: title_character=7'h20;
                endcase
            endcase
        end
    endfunction

    wire [7:0] font_data;
    font_rom font_i (.clk(clk), .ch(ch), .col(font_col), .data(font_data));
    reg text_area_d;
    reg [2:0] font_row_d;
    assign text_on = text_area_d && font_data[font_row_d];

    wire panel_now = (pixel_x >= 10'd24) && (pixel_x < 10'd616) &&
                     (pixel_y >= 10'd144) && (pixel_y < 10'd352);
    wire rim_now = panel_now && ((pixel_x < 10'd28) || (pixel_x >= 10'd612) ||
                                 (pixel_y < 10'd148) || (pixel_y >= 10'd348));
    always @(posedge clk) begin
        if (rst) begin
            panel_on <= 1'b0;
            accent_on <= 1'b0;
            text_area_d <= 1'b0;
            font_row_d <= 3'd0;
        end else begin
            panel_on <= active_video && panel_now;
            accent_on <= active_video && rim_now;
            text_area_d <= active_video && text_area;
            font_row_d <= font_row;
        end
    end
endmodule
