`timescale 1ns / 1ps
// 16x16 ROM at exactly 3x scale, centred in a black 96x64 OLED frame.
// The icon and source selection are held for a complete OLED frame by the top.
module oled_roulette_pixel (
    input wire clk,
    input wire [12:0] pixel_index,
    input wire [2:0] icon,
    output wire [15:0] pixel_data
);
    wire [6:0] x;
    wire [5:0] y;
    oled_xy xy_i(.pixel_index(pixel_index),.x(x),.y(y));
    wire inside_icon = x>=24 && x<72 && y>=8 && y<56 && pixel_index<6144;
    wire [6:0] dx=x-7'd24;
    wire [5:0] dy=y-6'd8;
    wire [3:0] local_x=dx/7'd3;
    wire [3:0] local_y=dy/6'd3;
    wire [15:0] rgb;
    reg inside_d=0;
    always @(posedge clk)inside_d<=inside_icon;
    item_icon_rom icon_i(.clk(clk),.icon(icon),.x(local_x),.y(local_y),.idx(),.rgb(rgb));
    assign pixel_data=inside_d ? rgb : 16'h0000;
endmodule
