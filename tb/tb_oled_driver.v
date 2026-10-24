`timescale 1ns / 1ps

// Self-checking testbench for oled_driver / oled_spi / font_rom (Story 4.1).
// A behavioural SSD1306 SPI slave logs every byte (with D/C and time). The test
// then checks: power-up order and delays, the exact init command order, the
// byte stream for a sample text (layout + glyph bytes), SPI mode 0 and the
// 10 MHz limit, and the power-down order. Simulates about 215 ms (real delays).
module tb_oled_driver;

    // SCALE shortens the millisecond delays (1 = real timing, about 12 min in
    // Icarus Verilog; 100 = same checks in seconds). Run with:
    //   iverilog -Ptb_oled_driver.SCALE=100 ...
    parameter integer SCALE = 1;
    localparam integer MS_NS = 1000000 / SCALE;      // one "millisecond" in ns

    reg          clk = 1'b0;
    reg          rst = 1'b1;
    reg          shutdown = 1'b0;
    reg  [511:0] status_text;
    wire         oled_on, oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;

    always #5 clk = ~clk;

    oled_driver #(.CYC_US(100), .CYC_MS(100000 / SCALE)) dut (
        .clk(clk), .rst(rst), .shutdown(shutdown), .status_text(status_text),
        .oled_on(oled_on), .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk),
        .oled_dc(oled_dc), .oled_res(oled_res), .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    // ---- sample text built only from the characters H E L O A and space ----
    function [7:0] sample_char;
        input integer k;
        integer v;
        begin
            v = (k * 5 + (k / 16) * 3) % 6;
            case (v)
                0: sample_char = "H";
                1: sample_char = "E";
                2: sample_char = "L";
                3: sample_char = "O";
                4: sample_char = "A";
                default: sample_char = " ";
            endcase
        end
    endfunction

    function [7:0] glyph_col;
        input [7:0] ch;
        input integer col;
        begin
            case (ch)
                "H": case (col) 0: glyph_col = 8'h7F; 1: glyph_col = 8'h08; 2: glyph_col = 8'h08; 3: glyph_col = 8'h08; default: glyph_col = 8'h7F; endcase
                "E": case (col) 0: glyph_col = 8'h7F; 1: glyph_col = 8'h49; 2: glyph_col = 8'h49; 3: glyph_col = 8'h49; default: glyph_col = 8'h41; endcase
                "L": case (col) 0: glyph_col = 8'h7F; default: glyph_col = 8'h40; endcase
                "O": case (col) 0: glyph_col = 8'h3E; 1: glyph_col = 8'h41; 2: glyph_col = 8'h41; 3: glyph_col = 8'h41; default: glyph_col = 8'h3E; endcase
                "A": case (col) 0: glyph_col = 8'h7E; 1: glyph_col = 8'h11; 2: glyph_col = 8'h11; 3: glyph_col = 8'h11; default: glyph_col = 8'h7E; endcase
                default: glyph_col = 8'h00;
            endcase
        end
    endfunction

    function [7:0] exp_data;
        input integer page;
        input integer n;
        integer cidx, kk;
        begin
            cidx = n / 8; kk = n % 8;
            if (kk >= 1 && kk <= 5) exp_data = glyph_col(sample_char(page * 16 + cidx), kk - 1);
            else                  exp_data = 8'h00;
        end
    endfunction

    integer ki;
    initial for (ki = 0; ki < 64; ki = ki + 1) status_text[ki * 8 +: 8] = sample_char(ki);

    // ---- SSD1306 SPI slave model ----
    reg [7:0]  log_byte [0:4095];
    reg        log_dc   [0:4095];
    time       log_time [0:4095];
    integer    log_n = 0;
    reg [7:0]  shreg;
    integer    bits = 0;
    time       last_sclk_rise = 0, min_period = 64'd1000000;
    reg        dc_at_start;
    integer    protocol_errors = 0;

    always @(posedge oled_sclk) begin
        if (oled_cs) begin protocol_errors = protocol_errors + 1; $display("FAIL: SCLK rose while CS high"); end
        else begin
            if (bits == 0) dc_at_start = oled_dc;
            if (oled_dc !== dc_at_start) begin protocol_errors = protocol_errors + 1; $display("FAIL: D/C changed inside a byte"); end
            shreg = {shreg[6:0], oled_mosi};
            bits = bits + 1;
            if (last_sclk_rise != 0 && ($time - last_sclk_rise) < min_period && bits > 1) min_period = $time - last_sclk_rise;
            last_sclk_rise = $time;
            if (bits == 8) begin
                log_byte[log_n] = shreg; log_dc[log_n] = dc_at_start; log_time[log_n] = $time;
                log_n = log_n + 1; bits = 0;
            end
        end
    end
    always @(negedge oled_cs) begin
        if (bits != 0) begin protocol_errors = protocol_errors + 1; $display("FAIL: CS fell in the middle of a byte"); end
        if (oled_sclk !== 1'b0) begin protocol_errors = protocol_errors + 1; $display("FAIL: SCLK not low when CS fell (mode 0)"); end
        bits = 0;
    end
    always @(posedge oled_cs) begin
        if (bits != 0) begin protocol_errors = protocol_errors + 1; $display("FAIL: CS rose after %0d bits", bits); bits = 0; end
    end

    // ---- supply / reset event times ----
    time t_vddc_fall [0:1];
    time t_vddc_rise [0:1];
    time t_vbat_fall [0:1];
    time t_vbat_rise [0:1];
    time t_res_fall, t_res_rise;
    integer n_vddc_fall = 0, n_vddc_rise = 0, n_vbat_fall = 0, n_vbat_rise = 0;
    integer log_at_vbat_fall, log_at_res_fall, log_at_res_rise;

    always @(negedge oled_vddc) begin if (n_vddc_fall < 2) t_vddc_fall[n_vddc_fall] = $time; n_vddc_fall = n_vddc_fall + 1; end
    always @(posedge oled_vddc) begin if (!rst) begin if (n_vddc_rise < 2) t_vddc_rise[n_vddc_rise] = $time; n_vddc_rise = n_vddc_rise + 1; end end
    always @(negedge oled_vbatc) begin if (n_vbat_fall < 2) t_vbat_fall[n_vbat_fall] = $time; if (n_vbat_fall == 0) log_at_vbat_fall = log_n; n_vbat_fall = n_vbat_fall + 1; end
    always @(posedge oled_vbatc) begin if (!rst) begin if (n_vbat_rise < 2) t_vbat_rise[n_vbat_rise] = $time; n_vbat_rise = n_vbat_rise + 1; end end
    always @(negedge oled_res) begin if (t_res_fall == 0) begin t_res_fall = $time; log_at_res_fall = log_n; end end
    always @(posedge oled_res) begin if (t_res_fall != 0 && t_res_rise == 0) begin t_res_rise = $time; log_at_res_rise = log_n; end end

    // ---- checking helpers ----
    integer errors = 0;
    integer ptr = 0;
    task fail; input [8*80-1:0] msg; begin errors = errors + 1; $display("FAIL: %0s", msg); end endtask

    task expect_cmd;
        input [7:0] b;
        begin
            if (ptr >= log_n) begin errors = errors + 1; $display("FAIL: log ended, wanted command %h", b); end
            else begin
                if (log_dc[ptr] !== 1'b0 || log_byte[ptr] !== b) begin
                    errors = errors + 1;
                    $display("FAIL: entry %0d is %s %h, wanted command %h", ptr, log_dc[ptr] ? "data" : "cmd", log_byte[ptr], b);
                end
                ptr = ptr + 1;
            end
        end
    endtask

    task expect_page;
        input integer page;
        integer n;
        begin
            expect_cmd(8'hB0 + page); expect_cmd(8'h00); expect_cmd(8'h10);
            for (n = 0; n < 128; n = n + 1) begin
                if (ptr >= log_n) begin errors = errors + 1; $display("FAIL: log ended in page %0d", page); n = 128; end
                else begin
                    if (log_dc[ptr] !== 1'b1 || log_byte[ptr] !== exp_data(page, n)) begin
                        if (errors < 20) $display("FAIL: page %0d byte %0d is %s %h, wanted data %h", page, n, log_dc[ptr] ? "data" : "cmd", log_byte[ptr], exp_data(page, n));
                        errors = errors + 1;
                    end
                    ptr = ptr + 1;
                end
            end
        end
    endtask

    integer p, wait_n;
    integer idx_AE, idx_A1, idx_AF, idx_last_data_before_vbat;
    time t_first_cmd, t_a1, t_af, t_last_pre_vbat;
    integer log_n_before_pd, ptr_pd;

    initial begin
        t_res_fall = 0; t_res_rise = 0;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // ---- first power-up ----
        wait_n = 0;
        while (!oled_on && wait_n < 30000000 / SCALE + 200000) begin @(posedge clk); wait_n = wait_n + 1; end
        if (!oled_on) fail("display never came on");
        // let a few full refresh passes complete
        repeat (400000) @(posedge clk);

        // ---- power-up order ----
        if (n_vddc_fall < 1) fail("VDDC never switched on");
        if (log_n == 0) fail("no SPI bytes");
        t_first_cmd = log_time[0];
        if (t_first_cmd - t_vddc_fall[0] < MS_NS) fail("first command less than 1 ms after VDDC on");
        if (t_res_rise - t_res_fall < 3000) fail("RES low pulse shorter than 3 us");
        if (log_at_res_fall != 1) fail("RES pulse not right after the display-off command");
        if (log_at_res_rise != 1) fail("commands sent while RES was low");

        // exact command/data order: init, one full screen write, VBAT, then the rest
        ptr = 0;
        expect_cmd(8'hAE);
        expect_cmd(8'h8D); expect_cmd(8'h14);
        expect_cmd(8'hD9); expect_cmd(8'hF1);
        for (p = 0; p < 4; p = p + 1) expect_page(p);
        t_last_pre_vbat = log_time[ptr - 1];
        if (log_at_vbat_fall != ptr) begin errors = errors + 1; $display("FAIL: VBATC switched on after %0d bytes, expected %0d (after init and the first full screen write)", log_at_vbat_fall, ptr); end
        if (t_vbat_fall[0] < t_last_pre_vbat) fail("VBATC on before the screen RAM was written");
        t_a1 = log_time[ptr];
        expect_cmd(8'hA1);
        if (t_a1 - t_vbat_fall[0] < 99 * MS_NS) fail("less than 100 ms between VBATC on and the next command");
        expect_cmd(8'hC8); expect_cmd(8'hDA); expect_cmd(8'h20);
        t_af = log_time[ptr];
        expect_cmd(8'hAF);
        if (t_af - t_vbat_fall[0] < 99 * MS_NS) fail("display on less than 100 ms after VBATC on");
        for (p = 0; p < 4; p = p + 1) expect_page(p);   // first refresh while running
        for (p = 0; p < 4; p = p + 1) expect_page(p);   // and a second one

        // ---- SPI quality ----
        if (min_period < 100) begin errors = errors + 1; $display("FAIL: SCLK period %0d ns, limit is 100 ns (10 MHz)", min_period); end
        if (protocol_errors != 0) errors = errors + protocol_errors;

        // ---- orderly power-down ----
        log_n_before_pd = log_n;
        @(negedge clk); shutdown = 1'b1;
        wait_n = 0;
        while (n_vddc_rise < 1 && wait_n < 25000000 / SCALE + 200000) begin @(posedge clk); wait_n = wait_n + 1; end
        if (n_vddc_rise < 1) fail("VDDC never switched off after shutdown");
        else begin
            if (n_vbat_rise < 1 || t_vbat_rise[0] > t_vddc_rise[0]) fail("VBATC must switch off before VDDC");
            if (t_vddc_rise[0] - t_vbat_rise[0] < 99 * MS_NS) fail("VDDC off less than 100 ms after VBATC off");
            // display-off command must be the last byte sent, before VBATC went off
            ptr_pd = log_n - 1;
            if (log_dc[ptr_pd] !== 1'b0 || log_byte[ptr_pd] !== 8'hAE) fail("last byte before power-down must be display off (0xAE)");
            if (log_time[ptr_pd] > t_vbat_rise[0]) fail("display off must be sent before VBATC off");
            if (oled_on) fail("oled_on still high after shutdown");
        end
        repeat (200000) @(posedge clk);
        if (n_vddc_fall != 1) fail("display powered up again while shutdown was still asserted");

        // ---- power back up ----
        log_n_before_pd = log_n;
        @(negedge clk); shutdown = 1'b0;
        wait_n = 0;
        while (log_n == log_n_before_pd && wait_n < 3000000) begin @(posedge clk); wait_n = wait_n + 1; end
        if (n_vddc_fall != 2) fail("VDDC did not switch on again after shutdown ended");
        else if (log_dc[log_n_before_pd] !== 1'b0 || log_byte[log_n_before_pd] !== 8'hAE) fail("second power-up must start with display off (0xAE)");
        else if (log_time[log_n_before_pd] - t_vddc_fall[1] < MS_NS) fail("second power-up: first command within 1 ms of VDDC on");

        $display("SPI SCLK min period %0d ns; %0d bytes logged; first power-up on after %0d us", min_period, log_n, (t_af - t_vddc_fall[0]) / 1000);
        if (errors == 0) $display("PASS: oled_driver - power-up order, init commands, text stream, SPI mode 0 <= 10 MHz, orderly power-down");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
