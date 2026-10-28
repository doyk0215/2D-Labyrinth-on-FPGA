`timescale 1ns / 1ps

// Fixed screen-space YOU WIN panel and green outline for Story 3.3.
// Outputs share render's one-clock pixel latency. The renderer decides when
// to show them from its frame snapshot of game_state; the maze stays behind.
module win_overlay (
    input  wire       clk,
    input  wire       rst,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active_video,
    output reg        panel_on,
    output reg        accent_on,
    output wire       text_on
);
    // 5x7 characters at 8x scale, one blank column between characters.
    // "YOU WIN" spans x=156..483, y=212..267, centred on the VGA picture.
    wire [9:0] text_x = pixel_x - 10'd156;
    wire [9:0] text_y = pixel_y - 10'd212;
    wire [5:0] text_col = text_x[8:3];
    reg [6:0] ch;
    reg [2:0] font_col;
    always @* begin
        ch = 7'h20;
        font_col = 3'd0;
        if (text_col < 6'd5) begin
            ch = "Y"; font_col = text_col;
        end else if (text_col >= 6'd6 && text_col < 6'd11) begin
            ch = "O"; font_col = text_col - 6'd6;
        end else if (text_col >= 6'd12 && text_col < 6'd17) begin
            ch = "U"; font_col = text_col - 6'd12;
        end else if (text_col >= 6'd24 && text_col < 6'd29) begin
            ch = "W"; font_col = text_col - 6'd24;
        end else if (text_col >= 6'd30 && text_col < 6'd35) begin
            ch = "I"; font_col = text_col - 6'd30;
        end else if (text_col >= 6'd36 && text_col < 6'd41) begin
            ch = "N"; font_col = text_col - 6'd36;
        end
    end

    wire [7:0] font_data;
    font_rom font_i (.clk(clk), .ch(ch), .col(font_col), .data(font_data));
    reg text_area_d;
    reg [2:0] text_row_d;
    assign text_on = text_area_d && font_data[text_row_d];

    wire panel_now = pixel_x >= 10'd132 && pixel_x < 10'd508 &&
                     pixel_y >= 10'd192 && pixel_y < 10'd288;
    wire panel_rim = panel_now && (pixel_x < 10'd136 || pixel_x >= 10'd504 ||
                                   pixel_y < 10'd196 || pixel_y >= 10'd284);
    wire screen_rim = pixel_x >= 10'd12 && pixel_x < 10'd628 &&
                      pixel_y >= 10'd12 && pixel_y < 10'd468 &&
                      (pixel_x < 10'd16 || pixel_x >= 10'd624 ||
                       pixel_y < 10'd16 || pixel_y >= 10'd464);
    always @(posedge clk) begin
        if (rst) begin
            panel_on <= 1'b0;
            accent_on <= 1'b0;
            text_area_d <= 1'b0;
            text_row_d <= 3'd0;
        end else begin
            panel_on <= active_video && panel_now;
            accent_on <= active_video && (screen_rim || panel_rim);
            text_area_d <= active_video && pixel_x >= 10'd156 && pixel_x < 10'd484 &&
                           pixel_y >= 10'd212 && pixel_y < 10'd268;
            text_row_d <= text_y[5:3];
        end
    end
endmodule
