`timescale 1ns / 1ps

// Story 10.1b: native VGA welcome page. All mutable display metadata is
// captured together in blanking. The glyph ROM and colour/mask flags share
// the renderer's one-clock latency. Input/menu/game logic is unchanged.
module welcome_menu_overlay #(
    parameter integer EASY_SECONDS=60, MEDIUM_SECONDS=120,
    parameter integer HARD_SECONDS=180, EPIC_SECONDS=240,
    parameter integer SECONDS_PER_CELL=12
) (
    input wire clk, rst, frame_tick,
    input wire [9:0] pixel_x, pixel_y,
    input wire active_video,
    input wire [2:0] selected_stage,
    input wire [4:0] custom_n,
    input wire [47:0] high_scores_bcd,
    output reg panel_on,
    output wire [11:0] rgb
);
    reg [2:0] stage_snap;
    reg [4:0] custom_snap;
    reg [47:0] scores_snap;
    always @(posedge clk) begin
        if (rst) begin stage_snap<=0; custom_snap<=5; scores_snap<=0; end
        else if (frame_tick) begin
            stage_snap <= (selected_stage <= 4) ? selected_stage : 0;
            custom_snap <= custom_n;
            scores_snap <= high_scores_bcd;
        end
    end
    function [7:0] digit;
        input [3:0] value;
        digit = value <= 9 ? 8'h30+value : 8'h3f;
    endfunction
    function [15:0] decimal2;
        input [5:0] value;
        reg [3:0] tens;
        begin
            tens=value>=40 ? 4 : value>=30 ? 3 : value>=20 ? 2 : value>=10 ? 1 : 0;
            decimal2={digit(tens),digit(value-10*tens)};
        end
    endfunction
    function [15:0] time_bcd;
        input integer seconds;
        integer total, mins, secs;
        begin
            total=seconds<0 ? 0 : seconds>5999 ? 5999 : seconds;
            mins=total/60; secs=total%60;
            time_bcd[15:12]=mins/10; time_bcd[11:8]=mins%10;
            time_bcd[7:4]=secs/10; time_bcd[3:0]=secs%10;
        end
    endfunction
    // This table is elaborated from parameters; no runtime timer division.
    wire [15:0] custom_time [0:31];
    genvar ti;
    generate for(ti=0;ti<32;ti=ti+1) begin : time_table
        assign custom_time[ti]=time_bcd(ti==5 ? EASY_SECONDS : ti==10 ? MEDIUM_SECONDS :
                                      ti==15 ? HARD_SECONDS : ti==20 ? EPIC_SECONDS : ti*SECONDS_PER_CELL);
    end endgenerate
    function [47:0] stage_word;
        input [2:0] stage;
        case(stage)
            0: stage_word="EASY  "; 1: stage_word="MEDIUM";
            2: stage_word="HARD  "; 3: stage_word="EPIC  ";
            default: stage_word="CUSTOM";
        endcase
    endfunction
    wire [4:0] selected_n=stage_snap==0 ? 5 : stage_snap==1 ? 10 : stage_snap==2 ? 15 : stage_snap==3 ? 20 : custom_snap;
    wire [15:0] map_digits=decimal2({selected_n,1'b0}+6'd1);
    wire [15:0] time_digits=stage_snap==0 ? time_bcd(EASY_SECONDS) :
                            stage_snap==1 ? time_bcd(MEDIUM_SECONDS) :
                            stage_snap==2 ? time_bcd(HARD_SECONDS) :
                            stage_snap==3 ? time_bcd(EPIC_SECONDS) : custom_time[custom_snap];
    reg [11:0] best_score;
    always @* case(stage_snap)
        0: best_score=scores_snap[11:0]; 1: best_score=scores_snap[23:12];
        2: best_score=scores_snap[35:24]; 3: best_score=scores_snap[47:36];
        default: best_score=0;
    endcase

    wire panel_now=(pixel_x>=48 && pixel_x<584 && pixel_y>=26 && pixel_y<444) ||
                   (pixel_x>=56 && pixel_x<592 && pixel_y>=34 && pixel_y<452);
    wire [9:0] selected_top=10'd184+({7'd0,stage_snap}<<5)+({7'd0,stage_snap}<<1);
    wire selected_box=pixel_x>=76 && pixel_x<328 && pixel_y>=selected_top && pixel_y<selected_top+28;
    reg [11:0] background_rgb;
    always @* begin
        background_rgb=12'h111;
        if(pixel_x>=48 && pixel_x<584 && pixel_y>=26 && pixel_y<444) background_rgb=12'h444;
        if(pixel_x>=50 && pixel_x<582 && pixel_y>=28 && pixel_y<442 &&
           (pixel_x<52 || pixel_x>=580 || pixel_y<30 || pixel_y>=440)) background_rgb=12'haaa;
        if(pixel_x>=56 && pixel_x<576 && pixel_y>=34 && pixel_y<436) background_rgb=12'h112;
        if(pixel_x>=348 && pixel_x<552 && pixel_y>=186 && pixel_y<362)
            background_rgb=(pixel_x==348 || pixel_x==551 || pixel_y==186 || pixel_y==361) ? 12'h556 : 12'h223;
        if(pixel_x>=364 && pixel_x<=535 && pixel_y==235) background_rgb=12'h556;
        if(pixel_x>=80 && pixel_x<=551 && (pixel_y==146 || pixel_y==376)) background_rgb=12'h555;
        if(pixel_x==320 && pixel_y>=387 && pixel_y<=432) background_rgb=12'h334;
        if(selected_box) begin
            background_rgb=(pixel_x<78 || pixel_x>=326 || pixel_y<selected_top+2 || pixel_y>=selected_top+26) ? 12'h6dd : 12'h134;
            if(pixel_x>=85 && pixel_x<=91 && pixel_y>=selected_top+7+(pixel_x-85) &&
               pixel_y<=selected_top+19-(pixel_x-85)) background_rgb=12'h6dd;
        end
    end

    // Select one text region, then address the shared 5x7 font. Long strings
    // are immutable; only stage/size/score/time characters depend on snapshots.
    integer line_id, ox, oy, scale, length, row_stage, row_n;
    reg [9:0] dx, dy;
    integer cell_index, glyph_col, glyph_row;
    reg [231:0] line;
    reg [15:0] size_digits;
    reg [11:0] foreground_rgb;
    reg text_area;
    reg [6:0] ch;
    always @* begin
        line_id=-1; ox=0; oy=0; scale=2; length=0; row_stage=0; row_n=5;
        foreground_rgb=12'hfff; line=0; size_digits=0;
        if(pixel_y>=48 && pixel_y<62) begin line_id=0; ox=261; oy=48; length=10; foreground_rgb=12'hbbb; end
        else if(pixel_y>=76 && pixel_y<104) begin line_id=1; ox=130; oy=76; scale=4; length=16; end
        else if(pixel_y>=116 && pixel_y<130) begin line_id=2; ox=147; oy=116; length=29; foreground_rgb=12'haaa; end
        else if(pixel_y>=160 && pixel_y<174) begin line_id=3; ox=80; oy=160; length=12; foreground_rgb=12'hddd; end
        else if(pixel_y>=201 && pixel_y<222 && pixel_x>=348) begin
            line_id=6; ox=(stage_snap==0 || stage_snap==2 || stage_snap==3) ? 416 : 398;
            oy=201; scale=3; length=(stage_snap==0 || stage_snap==2 || stage_snap==3) ? 4 : 6;
        end else if(pixel_y>=250 && pixel_y<264 && pixel_x>=348) begin line_id=7; ox=364; oy=250; length=11; foreground_rgb=12'hbbb; end
        else if(pixel_y>=279 && pixel_y<293 && pixel_x>=348) begin line_id=8; ox=364; oy=279; length=11; foreground_rgb=12'hbbb; end
        else if(pixel_y>=311 && pixel_y<325 && pixel_x>=348) begin line_id=9; ox=391; oy=311; length=10; foreground_rgb=12'h999; end
        else if(pixel_y>=337 && pixel_y<351 && pixel_x>=348) begin
            line_id=10; ox=stage_snap==4 ? 439 : 433; oy=337; length=stage_snap==4 ? 2 : 3; foreground_rgb=12'h6dd;
        end else if(pixel_y>=393 && pixel_y<407) begin
            oy=393;
            if(pixel_x<320) begin line_id=11; ox=131; length=10; foreground_rgb=12'hbbb; end
            else begin line_id=12; ox=409; length=7; foreground_rgb=12'h6dd; end
        end else if(pixel_y>=417 && pixel_y<431) begin
            oy=417; foreground_rgb=12'haaa;
            if(pixel_x<320) begin line_id=13; ox=131; length=10; end
            else begin line_id=14; ox=367; length=14; end
        end
        // Five non-overlapping stage rows on the left.
        if(pixel_x<328) begin
            if(pixel_y>=190 && pixel_y<204) begin row_stage=0; oy=190; end
            else if(pixel_y>=224 && pixel_y<238) begin row_stage=1; oy=224; end
            else if(pixel_y>=258 && pixel_y<272) begin row_stage=2; oy=258; end
            else if(pixel_y>=292 && pixel_y<306) begin row_stage=3; oy=292; end
            else if(pixel_y>=326 && pixel_y<340) begin row_stage=4; oy=326; end
            else row_stage=-1;
            if(row_stage>=0) begin
                scale=2;
                row_n=row_stage==0 ? 5 : row_stage==1 ? 10 : row_stage==2 ? 15 : row_stage==3 ? 20 : custom_snap;
                if(pixel_x<250) begin
                    line_id=4; ox=102; length=6; foreground_rgb=row_stage==stage_snap ? 12'hfff : 12'hbbb;
                end else begin
                    line_id=5; ox=264; length=row_n<10 ? 3 : 4; foreground_rgb=row_stage==stage_snap ? 12'h9cc : 12'h888;
                end
            end
        end
        size_digits=decimal2(row_n);
        case(line_id)
            0: line="WELCOME TO";
            1: line="LABYRINTH RUNNER";
            2: line="TILT THE MAZE. FIND THE EXIT.";
            3: line="SELECT STAGE";
            4: line=stage_word(row_stage);
            5: line=row_n<10 ? {"N=",size_digits[7:0]} : {"N=",size_digits};
            6: line=(length==4) ? (stage_word(stage_snap)>>16) : stage_word(stage_snap);
            7: line={"MAZE  ",map_digits,"X",map_digits};
            8: line={"TIME  ",digit(time_digits[15:12]),digit(time_digits[11:8]),":",digit(time_digits[7:4]),digit(time_digits[3:0])};
            9: line="HIGH SCORE";
            10: line=stage_snap==4 ? "--" : {digit(best_score[11:8]),digit(best_score[7:4]),digit(best_score[3:0])};
            11: line="U/D SELECT"; 12: line="C START";
            13: line="L SETTINGS"; 14: line="R INSTRUCTIONS";
            default: line=0;
        endcase
        dx=pixel_x-ox; dy=pixel_y-oy;
        cell_index=0; glyph_col=0; glyph_row=0; ch=7'h20; text_area=0;
        if(line_id>=0 && pixel_x>=ox && pixel_y>=oy) begin
            // Constant divisors only; a variable font scale must never infer
            // a general divider in the per-pixel datapath.
            if(scale==4) begin cell_index=dx/24; glyph_col=(dx%24)>>2; glyph_row=dy>>2; end
            else if(scale==3) begin cell_index=dx/18; glyph_col=(dx%18)/3; glyph_row=dy/3; end
            else begin cell_index=dx/12; glyph_col=(dx%12)>>1; glyph_row=dy>>1; end
            if(cell_index<length && glyph_col<5 && glyph_row<7) begin
                ch=line[(length-1-cell_index)*8+:7]; text_area=1;
            end
        end
    end
    wire [7:0] font_data;
    font_rom font_i(.clk(clk),.ch(ch),.col(glyph_col[2:0]),.data(font_data));
    reg text_area_d;
    reg [2:0] row_d;
    reg [11:0] foreground_d, background_d;
    always @(posedge clk) begin
        if(rst) begin panel_on<=0; text_area_d<=0; row_d<=0; foreground_d<=0; background_d<=0; end
        else begin
            panel_on<=active_video && panel_now;
            text_area_d<=active_video && text_area;
            row_d<=glyph_row[2:0]; foreground_d<=foreground_rgb; background_d<=background_rgb;
        end
    end
    assign rgb=text_area_d && font_data[row_d] ? foreground_d : background_d;
endmodule
