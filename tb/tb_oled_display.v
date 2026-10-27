`timescale 1ns / 1ps

// Self-checking testbench for the unmodified Oled_Display on a divided
// 6.25 MHz clock (oled_rgb_bringup_top). A behavioural SSD1331 SPI slave logs
// every byte. Checks: SCLK 6.25 MHz and idle high, CS framing, the exact init
// command bytes (D/C low), RES/VCCEN/PMODEN sequencing, then the first frame of
// 6144 pixels (12288 data bytes, D/C high) against an independent model:
//   TEXT = 0 : the colour-bar test pattern (oled_test_pattern)
//   TEXT = 1 : the four text lines, 6 px per character, 16 px per row, drawn
//              from font_rom with the layout re-derived here
// Simulates about 200 ms (real delays). Run with the glbl module and -L unisims_ver:
//   xelab tb_oled_display glbl -L unisims_ver --timescale 1ns/1ps -generic_top "TEXT=1"
module tb_oled_display;

    parameter integer TEXT = 0;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    always #5 clk = ~clk;

    wire [15:0] led;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vccen, oled_pmoden;

    oled_rgb_bringup_top dut (
        .clk(clk), .btnC(btnC), .sw(TEXT ? 16'h0000 : 16'h0001), .led(led),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk),
        .oled_dc(oled_dc), .oled_res(oled_res),
        .oled_vbatc(oled_vccen), .oled_vddc(oled_pmoden)
    );

    // ---- expected image models ----
    reg  [12:0] chk_index;
    wire [15:0] chk_data;
    oled_test_pattern chk_i (.pixel_index(chk_index), .pixel_data(chk_data));

    reg  [6:0]  exp_ch;
    reg  [2:0]  exp_col;
    wire [7:0]  exp_font;
    font_rom fexp (.clk(clk), .ch(exp_ch), .col(exp_col), .data(exp_font));

    reg [127:0] row0, row1, row2, row3;
    initial begin
        row0 = "2D LABYRINTH    ";
        row1 = "OLED TEST OK?   ";
        row2 = "ABC xyz 0123 !? ";
        row3 = "STAGE 1  00:00  ";
    end

    function [7:0] text_char;
        input integer r;
        input integer c;
        reg [127:0] s;
        begin
            case (r)
                0: s = row0;
                1: s = row1;
                2: s = row2;
                default: s = row3;
            endcase
            text_char = s[127 - 8 * c -: 8];
        end
    endfunction

    // ---- SSD1331 SPI slave model: SPI mode 3 (idle high, sample on rising edge) ----
    reg [7:0]  cmd_log [0:255];
    integer    cmd_n = 0;
    reg [15:0] pix_mem [0:6143];
    reg [7:0]  data_hi;
    integer    data_n = 0;          // data bytes seen
    reg [7:0]  sh;
    integer    bits = 0;
    time       t_last_rise, t_this_rise;
    integer    clk_period_err = 0;
    integer    cs_err = 0;
    time       t_res_fall, t_res_rise, t_vcc_rise, t_pmod_rise, t_afon;
    integer    errors = 0;

    // Sampled at the posedge of the 6.25 MHz clock (SCLK = clk while CS is low). Sampling on
    // posedge oled_sclk would also catch the edge as busy ends, a simulation race with CS.
    always @(posedge dut.clk_6m25) begin
        if (oled_cs === 1'b0) begin
            t_this_rise = $time;
            if (bits != 0 && (t_this_rise - t_last_rise) != 160)
                clk_period_err = clk_period_err + 1;
            t_last_rise = t_this_rise;
            sh = {sh[6:0], oled_mosi};
            bits = bits + 1;
            if (bits == 8) begin
                bits = 0;
                if (oled_dc === 1'b0) begin
                    cmd_log[cmd_n] = sh; cmd_n = cmd_n + 1;
                    if (sh == 8'hAF) t_afon = $time;
                end else begin
                    if (data_n[0] == 1'b0)
                        data_hi = sh;
                    else if (data_n / 2 < 6144)
                        pix_mem[data_n / 2] = {data_hi, sh};
                    data_n = data_n + 1;
                end
            end
        end
    end

    // a byte must not be cut short by CS, and SCLK must be high whenever CS is high
    always @(posedge oled_cs) begin
        if (bits != 0) begin cs_err = cs_err + 1; bits = 0; end
        if (oled_sclk !== 1'b1) cs_err = cs_err + 1;
    end

    always @(negedge oled_res) t_res_fall = $time;
    always @(posedge oled_res) t_res_rise = $time;
    always @(posedge oled_vccen) if (t_vcc_rise == 0) t_vcc_rise = $time;
    always @(posedge oled_pmoden) if (t_pmod_rise == 0) t_pmod_rise = $time;

    // expected command bytes, in the order Oled_Display sends them
    reg [7:0] exp_cmd [0:44];
    integer i, x, y, cx, gc, ty, line;
    reg [15:0] expected;
    integer pix_err = 0;
    initial begin
        t_vcc_rise = 0; t_pmod_rise = 0; t_res_fall = 0; t_res_rise = 0; t_afon = 0;
        exp_cmd[0]=8'hFD; exp_cmd[1]=8'h12; exp_cmd[2]=8'hAE; exp_cmd[3]=8'hA0; exp_cmd[4]=8'h72;
        exp_cmd[5]=8'hA1; exp_cmd[6]=8'h00; exp_cmd[7]=8'hA2; exp_cmd[8]=8'h00; exp_cmd[9]=8'hA4;
        exp_cmd[10]=8'hA8; exp_cmd[11]=8'h3F; exp_cmd[12]=8'hAD; exp_cmd[13]=8'h8E; exp_cmd[14]=8'hB0;
        exp_cmd[15]=8'h0B; exp_cmd[16]=8'hB1; exp_cmd[17]=8'h31; exp_cmd[18]=8'hB3; exp_cmd[19]=8'hF0;
        exp_cmd[20]=8'h8A; exp_cmd[21]=8'h64; exp_cmd[22]=8'h8B; exp_cmd[23]=8'h78; exp_cmd[24]=8'h8C;
        exp_cmd[25]=8'h64; exp_cmd[26]=8'hBB; exp_cmd[27]=8'h3A; exp_cmd[28]=8'hBE; exp_cmd[29]=8'h3E;
        exp_cmd[30]=8'h87; exp_cmd[31]=8'h06; exp_cmd[32]=8'h81; exp_cmd[33]=8'h91; exp_cmd[34]=8'h82;
        exp_cmd[35]=8'h50; exp_cmd[36]=8'h83; exp_cmd[37]=8'h7D; exp_cmd[38]=8'h25;
        exp_cmd[39]=8'h25; exp_cmd[40]=8'h00; exp_cmd[41]=8'h00; exp_cmd[42]=8'h5F; exp_cmd[43]=8'h3F;
        exp_cmd[44]=8'hAF; // ClearScreen is 25 00 00 5F 3F; then display on
    end

    initial begin
        // 20 ms power delay + 3 ms reset + 3 ms + init + 20 ms VCCEN + 100 ms + 1 frame (16.7 ms)
        #200_000_000;

        // --- init commands ---
        for (i = 0; i < 45; i = i + 1)
            if (cmd_log[i] !== exp_cmd[i]) begin
                $display("FAIL: command byte %0d = %h expected %h", i, cmd_log[i], exp_cmd[i]);
                errors = errors + 1;
            end

        // --- power sequencing ---
        if (t_pmod_rise == 0 || t_vcc_rise == 0 || !(t_pmod_rise < t_res_fall) || !(t_res_fall < t_vcc_rise)) begin
            $display("FAIL: sequence PMODEN %0t RES fall %0t VCCEN %0t", t_pmod_rise, t_res_fall, t_vcc_rise);
            errors = errors + 1;
        end
        if ((t_res_rise - t_res_fall) < 3000) begin
            $display("FAIL: RES low only %0t", t_res_rise - t_res_fall);
            errors = errors + 1;
        end
        if ((t_afon - t_vcc_rise) < 20_000_000) begin
            $display("FAIL: display-on %0t after VCCEN, expected >= 20 ms", t_afon - t_vcc_rise);
            errors = errors + 1;
        end

        // --- SPI ---
        if (clk_period_err != 0) begin
            $display("FAIL: %0d SCLK periods not 160 ns", clk_period_err); errors = errors + 1;
        end
        if (cs_err != 0) begin
            $display("FAIL: %0d CS/SCLK framing errors", cs_err); errors = errors + 1;
        end

        // --- first frame of pixels ---
        if (data_n < 12288) begin
            $display("FAIL: only %0d data bytes, expected a full frame (12288)", data_n);
            errors = errors + 1;
        end
        for (i = 0; i < 6144; i = i + 1) begin
            x = i % 96;
            y = i / 96;
            if (TEXT == 0) begin
                chk_index = i;
                #1;
                expected = chk_data;
            end else begin
                cx   = x / 6;
                gc   = x % 6;
                ty   = y / 16;
                line = (y % 16) / 2;
                exp_ch  = text_char(ty, cx);
                exp_col = (gc < 5) ? gc : 0;
                @(posedge clk); #1;
                expected = (gc < 5 && exp_font[line]) ? 16'hFFFF : 16'h0000;
            end
            if (pix_mem[i] !== expected) begin
                pix_err = pix_err + 1;
                if (pix_err <= 5)
                    $display("pixel %0d (x=%0d y=%0d) got %h expected %h", i, x, y, pix_mem[i], expected);
            end
        end
        if (pix_err != 0) begin
            $display("FAIL: %0d pixel mismatches", pix_err); errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: Oled_Display on 6.25 MHz - init bytes, power sequence, SPI timing, first 6144-pixel frame matches the %s",
                     TEXT ? "text image" : "test pattern");
        $finish;
    end

endmodule

// Wrapper used by the automated runner so the Vivado global startup model is
// included without applying the TEXT generic to the glbl design unit.
module tb_oled_display_with_glbl #(
    parameter integer TEXT = 0
);
    glbl glbl_i ();
    tb_oled_display #(.TEXT(TEXT)) oled_test_i ();
endmodule
