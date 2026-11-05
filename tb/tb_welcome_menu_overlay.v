`timescale 1ns / 1ps
module tb_welcome_menu_overlay;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, frame_tick=0, active_video=1;
    reg [9:0] x=0,y=0;
    reg [2:0] stage=1;
    reg [4:0] custom_n=12;
    reg [47:0] scores=48'h987123003001;
    wire panel;
    wire [11:0] rgb;
    welcome_menu_overlay dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),
        .pixel_x(x),.pixel_y(y),.active_video(active_video),
        .selected_stage(stage),.custom_n(custom_n),.high_scores_bcd(scores),
        .panel_on(panel),.rgb(rgb));
    reg [6:0] ref_ch=32;
    reg [2:0] ref_col=0;
    wire [7:0] ref_font_data;
    font_rom ref_font(.clk(clk),.ch(ref_ch),.col(ref_col),.data(ref_font_data));
    integer checked=0, file_out, px, py, s;
    reg [255:0] filename;
    task fail;
        input [511:0] reason;
        begin $display("FAIL welcome menu: %0s stage=%0d pixel=(%0d,%0d) rgb=%h",reason,stage,x,y,rgb); $finish; end
    endtask
    task frame;
        begin @(negedge clk); frame_tick=1; @(negedge clk); frame_tick=0; end
    endtask
    task pixel;
        input integer sx,sy;
        input [11:0] expected;
        begin
            @(negedge clk); x=sx; y=sy; @(posedge clk); #1;
            if(!panel || rgb!==expected) fail("panel/colour mismatch");
        end
    endtask
    // Independent reference character walk. Check all glyph and spacer pixels
    // in a text region, with a second font instance supplying the fixed art.
    task line_check;
        input [255:0] value;
        input integer len,ox,oy,scale;
        input [11:0] fg,bg;
        integer xx,yy,cell_index,col,row;
        reg [11:0] expected;
        begin
            for(yy=0;yy<7*scale;yy=yy+1)
                for(xx=0;xx<(6*len-1)*scale;xx=xx+1) begin
                    @(negedge clk); x=ox+xx; y=oy+yy;
                    cell_index=xx/(6*scale); col=(xx%(6*scale))/scale; row=yy/scale;
                    ref_ch=value[(len-1-cell_index)*8+:7]; ref_col=col;
                    @(posedge clk); #1;
                    expected=col<5 && ref_font_data[row] ? fg : bg;
                    if(!panel || rgb!==expected) begin
                        $display("expected=%h text=%s",expected,value);
                        fail("text raster mismatch");
                    end
                    checked=checked+1;
                end
        end
    endtask
    task capture;
        input integer index;
        begin
            $sformat(filename,"welcome_stage_%0d.ppm",index);
            file_out=$fopen(filename,"w");
            if(!file_out) fail("cannot open capture");
            $fwrite(file_out,"P3\n640 480\n255\n");
            for(py=0;py<480;py=py+1) for(px=0;px<640;px=px+1) begin
                @(negedge clk); x=px;y=py; @(posedge clk);#1;
                if(panel) $fwrite(file_out,"%0d %0d %0d\n",rgb[11:8]*17,rgb[7:4]*17,rgb[3:0]*17);
                else $fwrite(file_out,"0 0 34\n");
            end
            $fclose(file_out);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0; frame();
        line_check("WELCOME TO",10,261,48,2,12'hbbb,12'h112);
        line_check("LABYRINTH RUNNER",16,130,76,4,12'hfff,12'h112);
        line_check("TILT THE MAZE. FIND THE EXIT.",29,147,116,2,12'haaa,12'h112);
        line_check("SELECT STAGE",12,80,160,2,12'hddd,12'h112);
        line_check("MEDIUM",6,102,224,2,12'hfff,12'h134);
        line_check("N=10",4,264,224,2,12'h9cc,12'h134);
        line_check("MEDIUM",6,398,201,3,12'hfff,12'h223);
        line_check("MAZE  21X21",11,364,250,2,12'hbbb,12'h223);
        line_check("TIME  02:00",11,364,279,2,12'hbbb,12'h223);
        line_check("HIGH SCORE",10,391,311,2,12'h999,12'h223);
        line_check("003",3,433,337,2,12'h6dd,12'h223);
        line_check("U/D SELECT",10,131,393,2,12'hbbb,12'h112);
        line_check("C START",7,409,393,2,12'h6dd,12'h112);
        line_check("L SETTINGS",10,131,417,2,12'haaa,12'h112);
        line_check("R INSTRUCTIONS",14,367,417,2,12'haaa,12'h112);
        // Inputs must not tear a captured menu. A new frame changes all fields.
        stage=4;custom_n=20;scores=0;
        line_check("003",3,433,337,2,12'h6dd,12'h223);
        frame();
        line_check("CUSTOM",6,398,201,3,12'hfff,12'h223);
        line_check("MAZE  41X41",11,364,250,2,12'hbbb,12'h223);
        line_check("TIME  04:00",11,364,279,2,12'hbbb,12'h223);
        line_check("--",2,439,337,2,12'h6dd,12'h223);
        custom_n=5;frame();
        line_check("N=5",3,264,326,2,12'h9cc,12'h134);
        line_check("MAZE  11X11",11,364,250,2,12'hbbb,12'h223);
        // All four records use their own BCD slice, including multi-digit values.
        scores=48'h987123003001;
        for(s=0;s<4;s=s+1) begin
            stage=s; frame();
            case(s)
                0: begin line_check("001",3,433,337,2,12'h6dd,12'h223); line_check("TIME  01:00",11,364,279,2,12'hbbb,12'h223); end
                1: line_check("003",3,433,337,2,12'h6dd,12'h223);
                2: begin line_check("123",3,433,337,2,12'h6dd,12'h223); line_check("TIME  03:00",11,364,279,2,12'hbbb,12'h223); end
                3: begin line_check("987",3,433,337,2,12'h6dd,12'h223); line_check("TIME  04:00",11,364,279,2,12'hbbb,12'h223); end
            endcase
            capture(s);
        end
        stage=4;custom_n=12;frame();capture(4);
        line_check("TIME  02:24",11,364,279,2,12'hbbb,12'h223);
        pixel(50,28,12'haaa); pixel(348,186,12'h556); pixel(80,146,12'h555);
        @(negedge clk);active_video=0;@(posedge clk);#1;
        if(panel) fail("panel visible during blanking");
        $display("PASS: welcome menu title, symmetric hints, five stages, live size/time, independent high scores, CUSTOM, frame snapshots, blanking; %0d text pixels",checked);
        $finish;
    end
endmodule
