`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_time_pickup_hud;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, frame=0, init=0, bonus=0, video=1;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [9:0] x=0,y=0;
    reg [4:0] n=10;
    reg [3:0] effect=`ITEM_INVINCIBLE;
    wire panel,text_on,bonus_line,item_line,debuff_line;
    game_status_hud #(.CLK_HZ(4)) dut(
        .clk(clk),.rst(rst),.frame_tick(frame),.phys_init(init),.time_bonus_pulse(bonus),
        .pixel_x(x),.pixel_y(y),.active_video(video),.game_state(state),.n_cells(n),
        .minutes_bcd(8'h01),.seconds_bcd(8'h09),.warning_active(1'b0),.timer_flash_red(1'b0),
        .active_effect(effect),.effect_seconds(7'd8),.panel_on(panel),.text_on(text_on),
        .item_line(item_line),.debuff_line(debuff_line),.bonus_line(bonus_line));
    game_status_hud #(.CLK_HZ(4),.BONUS_SECONDS(125)) large_i(
        .clk(clk),.rst(rst),.frame_tick(frame),.phys_init(init),.time_bonus_pulse(bonus),
        .pixel_x(x),.pixel_y(y),.active_video(video),.game_state(state),.n_cells(n),
        .minutes_bcd(8'h01),.seconds_bcd(8'h09),.warning_active(1'b0),.timer_flash_red(1'b0),
        .active_effect(effect),.effect_seconds(7'd8));
    game_status_hud #(.CLK_HZ(4),.BONUS_SECONDS(0)) zero_i(
        .clk(clk),.rst(rst),.frame_tick(frame),.phys_init(init),.time_bonus_pulse(bonus),
        .pixel_x(x),.pixel_y(y),.active_video(video),.game_state(state),.n_cells(n),
        .minutes_bcd(8'h01),.seconds_bcd(8'h09),.warning_active(1'b0),.timer_flash_red(1'b0),
        .active_effect(effect),.effect_seconds(7'd8));
    task fail;input [767:0] why;
        begin $display("FAIL time pickup HUD: %0s",why);$fatal(1);end endtask
    task cycles;input integer count;begin repeat(count)@(negedge clk);end endtask
    task snap;begin frame=1;cycles(1);frame=0;end endtask
    task grant;begin bonus=1;cycles(1);bonus=0;end endtask
    reg [6:0] ref_ch;
    reg [2:0] ref_col;
    wire [7:0] ref_font;
    font_rom reference_font(.clk(clk),.ch(ref_ch),.col(ref_col),.data(ref_font));
    integer px,py,cell_index,col,row,checked=0;
    reg [159:0] expected_line;
    initial begin
        cycles(3);rst=0;cycles(1);
        if(dut.bonus_notice)fail("notice appeared without a grant");
        grant();
        if(dut.bonus_notice || dut.notice_left!=8)fail("grant did not wait for frame snapshot");
        snap();
        if(!dut.bonus_notice || zero_i.bonus_notice)fail("positive/zero grant qualification");
        if(large_i.item_status_line!=={"TIME BUFF +02:05",{4{8'h20}}})fail("configured bonus label");
        cycles(2);state=`ST_PAUSED;cycles(20);
        if(dut.notice_left!=5)fail("pause consumed notice duration");
        state=`ST_PLAY;cycles(4);
        if(dut.notice_left!=1)fail("notice expired early");
        cycles(1);
        if(dut.notice_left!=0 || !dut.bonus_notice)fail("expiry tore current frame");
        snap();if(dut.bonus_notice)fail("notice outlived next frame");
        if(dut.item_status_line!=={"BUFF INVINCIB 08s",{3{8'h20}}})fail("active buff was not restored");
        grant();cycles(3);grant();
        if(dut.notice_left!=8)fail("repeat pickup did not refresh notice");
        snap();
        // Exhaustively walk the actual text row with an independent glyph
        // position model. The held frame must retain both text and colour.
        expected_line={"TIME BUFF +10s",{6{8'h20}}};
        for(py=0;py<14;py=py+1) for(px=0;px<240;px=px+1) begin
            @(negedge clk);x=384+px;y=38+py;
            cell_index=px/12;col=(px%12)/2;row=py/2;
            ref_ch=expected_line[159-cell_index*8-:8];ref_col=col;
            @(posedge clk);#1;
            if(!panel || text_on!==(col<5 && ref_font[row]))fail("bonus glyph pixels");
            if(col<5 && (!bonus_line || !item_line || debuff_line))fail("bonus colour classification");
            checked=checked+1;
        end
        @(negedge clk);snap();
        effect=`ITEM_FOG;grant();snap();init=1;cycles(1);init=0;
        if(dut.bonus_notice || dut.notice_left!=0)fail("new maze retained notice");
        if(dut.item_status_line!=={"DEBUFF FOG      08s",8'h20})fail("debuff label changed");
        effect=`ITEM_NONE;grant();snap();state=`ST_MENU;cycles(1);
        if(dut.bonus_notice || dut.notice_left!=0)fail("menu retained notice");
        state=`ST_PLAY;n=5;grant();snap();x=385;y=40;cycles(2);
        if(text_on || bonus_line)fail("notice appeared on no-items EASY row");
        n=10;video=0;cycles(2);if(panel || text_on || bonus_line)fail("notice leaked into blanking");
        video=1;rst=1;cycles(2);if(panel || text_on || bonus_line || dut.bonus_notice)fail("reset retained notice");
        $display("PASS: time pickup HUD receipt, two-second lifetime, pause/refresh, frame stability, configured label, zero bonus, buff restore, reset and %0d glyph pixels",checked);
        $finish;
    end
    initial begin #200000;$display("FAIL time pickup HUD timeout");$fatal(1);end
endmodule
