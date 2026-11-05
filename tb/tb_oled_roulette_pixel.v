`timescale 1ns / 1ps
module tb_oled_roulette_pixel;
    reg clk=0;
    always #5 clk=~clk;
    reg [12:0] address=0;
    reg [3:0] icon=0;
    wire [15:0] pixel;
    oled_roulette_pixel dut(.clk(clk),.pixel_index(address),.icon(icon),.pixel_data(pixel));
    reg [1:0] indices[0:2303];
    reg [15:0] palette[0:35];
    integer i,a,x,y,lx,ly,rom_address,checked=0;
    reg [15:0] expected;
    initial begin
        $readmemh("item_icons.mem",indices);$readmemh("item_icons_palette.mem",palette);
        for(i=0;i<9;i=i+1)begin
            for(a=0;a<6144;a=a+1)begin
                @(negedge clk);icon=i;address=a;
                x=a%96;y=a/96;expected=0;
                if(x>=24 && x<72 && y>=8 && y<56)begin
                    lx=(x-24)/3;ly=(y-8)/3;rom_address=i*256+ly*16+lx;
                    expected=palette[i*4+indices[rom_address]];
                end
                @(posedge clk);#1;
                if(pixel!==expected)begin
                    $display("FAIL roulette pixel icon=%0d x=%0d y=%0d got=%h expected=%h",i,x,y,pixel,expected);$finish;
                end
                checked=checked+1;
            end
        end
        @(negedge clk);address=8191;@(posedge clk);#1;
        if(pixel!==0)begin $display("FAIL roulette pixel invalid address");$finish;end
        $display("PASS: OLED roulette pixel all 9 icons, 3x scale, centred 48x48 and black margins; %0d pixels match ROM data",checked);
        $finish;
    end
    initial begin #1000000;$display("FAIL roulette pixel timeout");$finish;end
endmodule
