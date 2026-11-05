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

    // Each line decodes fixed character boxes in parallel. This avoids a
    // serial y -> origin -> divide -> variable string shift path at 100 MHz.
    // The single synchronous font lookup still supplies one-clock latency.
    wire [15:0] custom_digits=decimal2({1'b0,custom_snap});
    wire hit_0; wire [6:0] ch_0; wire [2:0] col_0, row_0;
    welcome_text_line #(.LENGTH(10),.X(261),.Y(48),.SCALE(2)) text_0 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("WELCOME TO"),
        .hit(hit_0),.ch(ch_0),.col(col_0),.row(row_0));
    wire hit_1; wire [6:0] ch_1; wire [2:0] col_1, row_1;
    welcome_text_line #(.LENGTH(16),.X(130),.Y(76),.SCALE(4)) text_1 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("LABYRINTH RUNNER"),
        .hit(hit_1),.ch(ch_1),.col(col_1),.row(row_1));
    wire hit_2; wire [6:0] ch_2; wire [2:0] col_2, row_2;
    welcome_text_line #(.LENGTH(29),.X(147),.Y(116),.SCALE(2)) text_2 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("TILT THE MAZE. FIND THE EXIT."),
        .hit(hit_2),.ch(ch_2),.col(col_2),.row(row_2));
    wire hit_3; wire [6:0] ch_3; wire [2:0] col_3, row_3;
    welcome_text_line #(.LENGTH(12),.X(80),.Y(160),.SCALE(2)) text_3 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("SELECT STAGE"),
        .hit(hit_3),.ch(ch_3),.col(col_3),.row(row_3));
    wire hit_4; wire [6:0] ch_4; wire [2:0] col_4, row_4;
    welcome_text_line #(.LENGTH(6),.X(102),.Y(190),.SCALE(2)) text_4 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("EASY  "),
        .hit(hit_4),.ch(ch_4),.col(col_4),.row(row_4));
    wire hit_5; wire [6:0] ch_5; wire [2:0] col_5, row_5;
    welcome_text_line #(.LENGTH(3),.X(264),.Y(190),.SCALE(2)) text_5 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("N=5"),
        .hit(hit_5),.ch(ch_5),.col(col_5),.row(row_5));
    wire hit_6; wire [6:0] ch_6; wire [2:0] col_6, row_6;
    welcome_text_line #(.LENGTH(6),.X(102),.Y(224),.SCALE(2)) text_6 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("MEDIUM"),
        .hit(hit_6),.ch(ch_6),.col(col_6),.row(row_6));
    wire hit_7; wire [6:0] ch_7; wire [2:0] col_7, row_7;
    welcome_text_line #(.LENGTH(4),.X(264),.Y(224),.SCALE(2)) text_7 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("N=10"),
        .hit(hit_7),.ch(ch_7),.col(col_7),.row(row_7));
    wire hit_8; wire [6:0] ch_8; wire [2:0] col_8, row_8;
    welcome_text_line #(.LENGTH(6),.X(102),.Y(258),.SCALE(2)) text_8 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("HARD  "),
        .hit(hit_8),.ch(ch_8),.col(col_8),.row(row_8));
    wire hit_9; wire [6:0] ch_9; wire [2:0] col_9, row_9;
    welcome_text_line #(.LENGTH(4),.X(264),.Y(258),.SCALE(2)) text_9 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("N=15"),
        .hit(hit_9),.ch(ch_9),.col(col_9),.row(row_9));
    wire hit_10; wire [6:0] ch_10; wire [2:0] col_10, row_10;
    welcome_text_line #(.LENGTH(6),.X(102),.Y(292),.SCALE(2)) text_10 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("EPIC  "),
        .hit(hit_10),.ch(ch_10),.col(col_10),.row(row_10));
    wire hit_11; wire [6:0] ch_11; wire [2:0] col_11, row_11;
    welcome_text_line #(.LENGTH(4),.X(264),.Y(292),.SCALE(2)) text_11 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("N=20"),
        .hit(hit_11),.ch(ch_11),.col(col_11),.row(row_11));
    wire hit_12; wire [6:0] ch_12; wire [2:0] col_12, row_12;
    welcome_text_line #(.LENGTH(6),.X(102),.Y(326),.SCALE(2)) text_12 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("CUSTOM"),
        .hit(hit_12),.ch(ch_12),.col(col_12),.row(row_12));
    wire hit_13; wire [6:0] ch_13; wire [2:0] col_13, row_13;
    welcome_text_line #(.LENGTH(3),.X(264),.Y(326),.SCALE(2)) text_13 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(custom_snap<10),.text({"N=",custom_digits[7:0]}),
        .hit(hit_13),.ch(ch_13),.col(col_13),.row(row_13));
    wire hit_14; wire [6:0] ch_14; wire [2:0] col_14, row_14;
    welcome_text_line #(.LENGTH(4),.X(264),.Y(326),.SCALE(2)) text_14 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(custom_snap>=10),.text({"N=",custom_digits}),
        .hit(hit_14),.ch(ch_14),.col(col_14),.row(row_14));
    wire hit_15; wire [6:0] ch_15; wire [2:0] col_15, row_15;
    welcome_text_line #(.LENGTH(4),.X(416),.Y(201),.SCALE(3)) text_15 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(stage_snap==0 || stage_snap==2 || stage_snap==3),.text(stage_word(stage_snap)>>16),
        .hit(hit_15),.ch(ch_15),.col(col_15),.row(row_15));
    wire hit_16; wire [6:0] ch_16; wire [2:0] col_16, row_16;
    welcome_text_line #(.LENGTH(6),.X(398),.Y(201),.SCALE(3)) text_16 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(stage_snap==1 || stage_snap==4),.text(stage_word(stage_snap)),
        .hit(hit_16),.ch(ch_16),.col(col_16),.row(row_16));
    wire hit_17; wire [6:0] ch_17; wire [2:0] col_17, row_17;
    welcome_text_line #(.LENGTH(11),.X(364),.Y(250),.SCALE(2)) text_17 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text({"MAZE  ",map_digits,"X",map_digits}),
        .hit(hit_17),.ch(ch_17),.col(col_17),.row(row_17));
    wire hit_18; wire [6:0] ch_18; wire [2:0] col_18, row_18;
    welcome_text_line #(.LENGTH(11),.X(364),.Y(279),.SCALE(2)) text_18 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text({"TIME  ",digit(time_digits[15:12]),digit(time_digits[11:8]),":",digit(time_digits[7:4]),digit(time_digits[3:0])}),
        .hit(hit_18),.ch(ch_18),.col(col_18),.row(row_18));
    wire hit_19; wire [6:0] ch_19; wire [2:0] col_19, row_19;
    welcome_text_line #(.LENGTH(10),.X(391),.Y(311),.SCALE(2)) text_19 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("HIGH SCORE"),
        .hit(hit_19),.ch(ch_19),.col(col_19),.row(row_19));
    wire hit_20; wire [6:0] ch_20; wire [2:0] col_20, row_20;
    welcome_text_line #(.LENGTH(3),.X(433),.Y(337),.SCALE(2)) text_20 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(stage_snap!=4),.text({digit(best_score[11:8]),digit(best_score[7:4]),digit(best_score[3:0])}),
        .hit(hit_20),.ch(ch_20),.col(col_20),.row(row_20));
    wire hit_21; wire [6:0] ch_21; wire [2:0] col_21, row_21;
    welcome_text_line #(.LENGTH(2),.X(439),.Y(337),.SCALE(2)) text_21 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(stage_snap==4),.text("--"),
        .hit(hit_21),.ch(ch_21),.col(col_21),.row(row_21));
    wire hit_22; wire [6:0] ch_22; wire [2:0] col_22, row_22;
    welcome_text_line #(.LENGTH(10),.X(131),.Y(393),.SCALE(2)) text_22 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("U/D SELECT"),
        .hit(hit_22),.ch(ch_22),.col(col_22),.row(row_22));
    wire hit_23; wire [6:0] ch_23; wire [2:0] col_23, row_23;
    welcome_text_line #(.LENGTH(7),.X(409),.Y(393),.SCALE(2)) text_23 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("C START"),
        .hit(hit_23),.ch(ch_23),.col(col_23),.row(row_23));
    wire hit_24; wire [6:0] ch_24; wire [2:0] col_24, row_24;
    welcome_text_line #(.LENGTH(10),.X(131),.Y(417),.SCALE(2)) text_24 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("L SETTINGS"),
        .hit(hit_24),.ch(ch_24),.col(col_24),.row(row_24));
    wire hit_25; wire [6:0] ch_25; wire [2:0] col_25, row_25;
    welcome_text_line #(.LENGTH(14),.X(367),.Y(417),.SCALE(2)) text_25 (
        .pixel_x(pixel_x),.pixel_y(pixel_y),.enable(1'b1),.text("R INSTRUCTIONS"),
        .hit(hit_25),.ch(ch_25),.col(col_25),.row(row_25));
    wire [6:0] ch=ch_0 | ch_1 | ch_2 | ch_3 | ch_4 | ch_5 | ch_6 | ch_7 | ch_8 | ch_9 | ch_10 | ch_11 | ch_12 | ch_13 | ch_14 | ch_15 | ch_16 | ch_17 | ch_18 | ch_19 | ch_20 | ch_21 | ch_22 | ch_23 | ch_24 | ch_25;
    wire [2:0] glyph_col=col_0 | col_1 | col_2 | col_3 | col_4 | col_5 | col_6 | col_7 | col_8 | col_9 | col_10 | col_11 | col_12 | col_13 | col_14 | col_15 | col_16 | col_17 | col_18 | col_19 | col_20 | col_21 | col_22 | col_23 | col_24 | col_25;
    wire [2:0] glyph_row=row_0 | row_1 | row_2 | row_3 | row_4 | row_5 | row_6 | row_7 | row_8 | row_9 | row_10 | row_11 | row_12 | row_13 | row_14 | row_15 | row_16 | row_17 | row_18 | row_19 | row_20 | row_21 | row_22 | row_23 | row_24 | row_25;
    wire text_area=hit_0 | hit_1 | hit_2 | hit_3 | hit_4 | hit_5 | hit_6 | hit_7 | hit_8 | hit_9 | hit_10 | hit_11 | hit_12 | hit_13 | hit_14 | hit_15 | hit_16 | hit_17 | hit_18 | hit_19 | hit_20 | hit_21 | hit_22 | hit_23 | hit_24 | hit_25;
    wire [11:0] foreground_rgb=({12{hit_0}} & (12'hbbb)) |
        ({12{hit_1}} & (12'hfff)) |
        ({12{hit_2}} & (12'haaa)) |
        ({12{hit_3}} & (12'hddd)) |
        ({12{hit_4}} & (stage_snap==0 ? 12'hfff : 12'hbbb)) |
        ({12{hit_5}} & (stage_snap==0 ? 12'h9cc : 12'h888)) |
        ({12{hit_6}} & (stage_snap==1 ? 12'hfff : 12'hbbb)) |
        ({12{hit_7}} & (stage_snap==1 ? 12'h9cc : 12'h888)) |
        ({12{hit_8}} & (stage_snap==2 ? 12'hfff : 12'hbbb)) |
        ({12{hit_9}} & (stage_snap==2 ? 12'h9cc : 12'h888)) |
        ({12{hit_10}} & (stage_snap==3 ? 12'hfff : 12'hbbb)) |
        ({12{hit_11}} & (stage_snap==3 ? 12'h9cc : 12'h888)) |
        ({12{hit_12}} & (stage_snap==4 ? 12'hfff : 12'hbbb)) |
        ({12{hit_13}} & (stage_snap==4 ? 12'h9cc : 12'h888)) |
        ({12{hit_14}} & (stage_snap==4 ? 12'h9cc : 12'h888)) |
        ({12{hit_15}} & (12'hfff)) |
        ({12{hit_16}} & (12'hfff)) |
        ({12{hit_17}} & (12'hbbb)) |
        ({12{hit_18}} & (12'hbbb)) |
        ({12{hit_19}} & (12'h999)) |
        ({12{hit_20}} & (12'h6dd)) |
        ({12{hit_21}} & (12'h6dd)) |
        ({12{hit_22}} & (12'hbbb)) |
        ({12{hit_23}} & (12'h6dd)) |
        ({12{hit_24}} & (12'haaa)) |
        ({12{hit_25}} & (12'haaa));
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

// Fixed boxes make every character selection a small compare/AND/OR network.
// All ranges are elaboration constants, including the 3x selected-stage text.
module welcome_text_line #(
    parameter integer LENGTH=1, X=0, Y=0, SCALE=2
) (
    input wire [9:0] pixel_x,pixel_y,
    input wire enable,
    input wire [8*LENGTH-1:0] text,
    output wire hit,
    output wire [6:0] ch,
    output wire [2:0] col,row
);
    wire in_y=enable && pixel_y>=Y && pixel_y<Y+7*SCALE;
    wire [LENGTH-1:0] boxes;
    wire [6:0] chars [0:LENGTH];
    wire [2:0] cols [0:LENGTH];
    assign chars[0]=0;
    assign cols[0]=0;
    genvar c;
    generate for(c=0;c<LENGTH;c=c+1) begin : character
        localparam integer LEFT=X+c*6*SCALE;
        assign boxes[c]=in_y && pixel_x>=LEFT && pixel_x<LEFT+5*SCALE;
        wire [2:0] local_col=pixel_x>=LEFT+4*SCALE ? 4 :
                             pixel_x>=LEFT+3*SCALE ? 3 :
                             pixel_x>=LEFT+2*SCALE ? 2 :
                             pixel_x>=LEFT+SCALE ? 1 : 0;
        assign chars[c+1]=chars[c] | ({7{boxes[c]}} & text[(LENGTH-1-c)*8+:7]);
        assign cols[c+1]=cols[c] | ({3{boxes[c]}} & local_col);
    end endgenerate
    assign hit=|boxes;
    assign ch=chars[LENGTH];
    assign col=cols[LENGTH];
    wire [2:0] local_row=pixel_y>=Y+6*SCALE ? 6 :
                         pixel_y>=Y+5*SCALE ? 5 :
                         pixel_y>=Y+4*SCALE ? 4 :
                         pixel_y>=Y+3*SCALE ? 3 :
                         pixel_y>=Y+2*SCALE ? 2 :
                         pixel_y>=Y+SCALE ? 1 : 0;
    assign row={3{hit}} & local_row;
endmodule
