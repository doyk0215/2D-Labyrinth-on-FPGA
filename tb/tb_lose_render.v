`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Independent row-bitmap model checks every active and blanking pixel.
// ball_on is high so the panel must outrank the ball at every covered pixel.
module tb_lose_render;
    reg clk=0, rst=1, frame_tick=0;
    always #5 clk=~clk;
    reg [`GAME_STATE_W-1:0] game_state=`ST_PLAY;
    reg [9:0] x=0,y=0;
    reg active=1,hs=1,vs=1,ball_on=1;
    wire [3:0] r,g,b;
    wire out_hs,out_vs;
    render dut (
        .clk(clk),.rst(rst),.ce_pix(1'b0),.frame_tick(frame_tick),.game_state(game_state),
        .time_min_bcd(8'h00),.time_sec_bcd(8'h00),.n_cells(4'd10),
        .cam_x(18'sd0),.cam_y(18'sd0),.angle(12'd0),.sin_q(16'sd0),.cos_q(16'sd16384),
        .pixel_x(x),.pixel_y(y),.active_video(active),.hsync_in(hs),.vsync_in(vs),
        .maze_raddr(),.maze_rdata(1'b1),.start_col(5'd19),.start_row(5'd19),
        .goal_col(5'd1),.goal_row(5'd1),.ball_on(ball_on),.fog_en(1'b0),.fog_clear(1'b0),
        .vga_r(r),.vga_g(g),.vga_b(b),.vga_hs(out_hs),.vga_vs(out_vs),.sin_snap(),.cos_snap()
    );
    task fail;
        input [511:0] message;
        begin $display("FAIL lose render: %0s at (%0d,%0d), RGB=%h",message,x,y,{r,g,b}); $fatal(1); end
    endtask
    task frame;
        begin @(negedge clk);frame_tick=1; @(negedge clk);frame_tick=0;
            repeat(3) @(negedge clk); end
    endtask
    task pixel;
        input integer px,py;
        input [11:0] expected;
        begin @(negedge clk);x=px;y=py; @(posedge clk);#1;
            if({r,g,b} !== expected) fail("pixel mismatch"); end
    endtask
    // Font rows are written independently of font_rom's column table.
    function title_pixel;
        input integer px,py;
        integer char_slot,column,row;
        reg [34:0] rows;
        begin
            title_pixel=0;
            if(px>=156 && px<484 && py>=212 && py<268) begin
                char_slot=(px-156)/48; column=((px-156)%48)/8; row=(py-212)/8;
                case(char_slot)
                    0:rows={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100}; // T
                    1:rows={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110}; // I
                    2:rows={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001}; // M
                    3:rows={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111}; // E
                    5:rows={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110}; // U
                    6:rows={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000}; // P
                    default:rows=0;
                endcase
                if(column<5) title_pixel=rows[(6-row)*5+4-column];
            end
        end
    endfunction
    function [11:0] model;
        input integer px,py;
        reg panel,rim;
        begin
            panel=px>=140 && px<500 && py>=192 && py<288;
            rim=(panel && (px<144 || px>=496 || py<196 || py>=284)) ||
                (px>=12 && px<628 && py>=12 && py<468 &&
                 (px<16 || px>=624 || py<16 || py>=464));
            if(px>=640 || py>=480) model=12'h000;
            else if(panel || rim) begin
                if(title_pixel(px,py)) model=12'hfff;
                else if(rim) model=12'hf22;
                else model=12'h300;
            end else model=12'hfc0;
        end
    endfunction
    integer px,py,checked=0;
    initial begin
        repeat(3) @(negedge clk); rst=0;
        pixel(156,212,12'hfc0);
        game_state=`ST_LOSE;
        pixel(156,212,12'hfc0); // no change before frame snapshot
        frame(); pixel(156,212,12'hfff); pixel(140,192,12'hf22);
        for(py=0;py<525;py=py+1) begin
            for(px=0;px<800;px=px+1) begin
                @(negedge clk);
                x=px;y=py;active=(px<640 && py<480);
                hs=!(px>=656 && px<752);vs=!(py>=490 && py<492);
                @(posedge clk);#1;
                if({r,g,b} !== model(px,py)) fail("raster differs from independent glyph/panel model");
                if(out_hs !== hs || out_vs !== vs) fail("sync not aligned with one-clock pixels");
                checked=checked+1;
            end
        end
        active=1;hs=1;vs=1;
        game_state=`ST_WIN; pixel(140,192,12'hf22); // no mid-frame overlay switch
        frame(); pixel(140,192,12'h0f0); // WIN overlay unchanged
        game_state=`ST_LOSE; frame(); pixel(140,192,12'hf22);
        game_state=`ST_PLAY; pixel(140,192,12'hf22); frame(); pixel(140,192,12'hfc0);
        game_state=`ST_LOSE; frame(); rst=1;
        pixel(156,212,12'h000); rst=0; pixel(156,212,12'hfc0);
        if(dut.lose_frame || dut.win_frame) fail("reset retained a result frame");
        $display("PASS: lose render TIME UP glyphs, red panel, priority, frame latch, reset, blanking and sync; %0d pixels",checked);
        $finish;
    end
    initial begin #10000000; fail("timeout"); end
endmodule
