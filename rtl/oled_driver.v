`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// oled_driver: Digilent Pmod OLED (128x32, SSD1306, SPI) text display (Story 4.1, AD-10).
//
// Shows `status_text`: 64 ASCII characters = 4 rows x 16 columns. Character k
// (k = row*16 + column, row 0 at the top) is status_text[8*k +: 8], so the
// top-left character is status_text[7:0]. Each character is an 8x8 cell
// (1 blank column, 5 glyph columns, 2 blank columns); one text row = one
// display page (8 pixel rows). The driver refreshes all four pages in a loop.
//
// Power-up order (Digilent Pmod OLED manual): VDDC on -> wait -> Display Off
// -> RES pulse -> charge pump / pre-charge -> write the screen -> VBATC on ->
// wait 100 ms -> Display On. VDDC and VBATC are ACTIVE LOW (0 = supply on).
// Power-down (`shutdown` = 1): Display Off -> VBATC off -> wait 100 ms ->
// VDDC off. `rst` forces both supplies off at once (use it only for FPGA
// start-up; use `shutdown` for an orderly stop). `shutdown` is honoured between
// refresh passes once the display is running.
//
// The init commands are in `init_cmd` below, so they are easy to adjust if the
// real panel needs different values (see the NOTE there).
module oled_driver #(
    parameter integer CYC_US = 100,       // clocks per microsecond (100 MHz clock)
    parameter integer CYC_MS = 100000     // clocks per millisecond; only reduce this to speed up simulation
) (
    input  wire         clk,           // 100 MHz
    input  wire         rst,
    input  wire         shutdown,      // 1 = power the display down in order
    input  wire [511:0] status_text,
    output reg          oled_on,       // 1 while the display is on and refreshing
    output wire         oled_cs,
    output wire         oled_mosi,
    output wire         oled_sclk,
    output wire         oled_dc,
    output reg          oled_res,
    output reg          oled_vbatc,
    output reg          oled_vddc
);

    // ---- SPI byte engine ----
    reg        spi_start;
    reg        spi_dc;
    reg  [7:0] spi_data;
    wire       spi_busy;
    oled_spi spi_i (
        .clk(clk), .rst(rst), .start(spi_start), .dc_in(spi_dc), .data(spi_data),
        .busy(spi_busy), .cs_n(oled_cs), .sclk(oled_sclk), .mosi(oled_mosi), .dc(oled_dc)
    );

    // ---- font ----
    reg  [1:0] page;                          // text row / display page 0..3
    reg  [6:0] n;                             // byte index inside the page 0..127
    wire [5:0] char_idx = {page, n[6:3]};
    wire [7:0] ch_byte  = status_text[{char_idx, 3'b000} +: 8];
    wire [2:0] fcol     = n[2:0] - 3'd1;      // glyph column 0..4 for n[2:0] = 1..5
    wire       in_glyph = (n[2:0] >= 3'd1) && (n[2:0] <= 3'd5);
    wire [7:0] font_data;
    font_rom font_i (.clk(clk), .ch(ch_byte[6:0]), .col(fcol), .data(font_data));

    // ---- init command table ----
    // NOTE: follows the Digilent Pmod OLED sequence (0xAE, reset, 0x8D 0x14,
    // 0xD9 0xF1, VBAT on + 100 ms, 0xA1, 0xC8, 0xDA 0x20, 0xAF). Not yet
    // checked on the real panel: if the picture is upside down, mirrored or
    // every other line is missing, change 0xA1 / 0xC8 / 0xDA 0x20 here.
    function [7:0] init_cmd;
        input [3:0] i;
        begin
            case (i)
                4'd0:  init_cmd = 8'hAE;      // display off
                4'd1:  init_cmd = 8'h8D;      // charge pump setting
                4'd2:  init_cmd = 8'h14;      //   enable
                4'd3:  init_cmd = 8'hD9;      // pre-charge period
                4'd4:  init_cmd = 8'hF1;
                4'd5:  init_cmd = 8'hA1;      // segment re-map
                4'd6:  init_cmd = 8'hC8;      // COM scan direction
                4'd7:  init_cmd = 8'hDA;      // COM pins configuration
                4'd8:  init_cmd = 8'h20;
                default: init_cmd = 8'hAF;    // display on
            endcase
        end
    endfunction

    // ---- sequencer ----
    localparam [4:0]
        M_OFF       = 5'd0,
        M_DLY       = 5'd1,   // generic delay (dly_cnt), then `after`
        M_TX        = 5'd2,   // generic byte send, then `after`
        M_TX_WAIT   = 5'd3,
        M_TX_WAIT2  = 5'd4,
        M_STEP      = 5'd5,   // power-up step dispatcher
        M_RUN       = 5'd6,
        M_PD        = 5'd7,   // power-down dispatcher
        R_CMD       = 5'd8,   // refresh: page/column commands
        R_FETCH     = 5'd9,
        R_FWAIT     = 5'd10,
        R_DATA      = 5'd11,
        R_NEXT      = 5'd12;

    reg [4:0]  state, after;
    reg [23:0] dly_cnt;
    reg [4:0]  step;           // power-up / power-down step
    reg [1:0]  cmdn;           // 0..2 inside R_CMD
    reg        in_run;         // 1 once the display is on (refresh loop)
    reg        ret_run;        // refresh return target: 0 = continue power-up, 1 = loop

    task start_tx;
        input        dc_v;
        input [7:0]  b;
        input [4:0]  next;
        begin
            spi_dc <= dc_v; spi_data <= b; spi_start <= 1'b1;
            after <= next; state <= M_TX;
        end
    endtask

    task start_delay;
        input [23:0] cycles;
        input [4:0]  next;
        begin
            dly_cnt <= cycles - 24'd1; after <= next; state <= M_DLY;
        end
    endtask

    always @(posedge clk) begin
        spi_start <= 1'b0;
        if (rst) begin
            state <= M_OFF; after <= M_OFF; step <= 5'd0; page <= 2'd0; n <= 7'd0; cmdn <= 2'd0;
            oled_vddc <= 1'b1; oled_vbatc <= 1'b1; oled_res <= 1'b1; oled_on <= 1'b0;
            in_run <= 1'b0; ret_run <= 1'b0; dly_cnt <= 24'd0;
            spi_dc <= 1'b0; spi_data <= 8'd0;
        end else begin
            case (state)
                // ---------------- off: wait, then power up ----------------
                M_OFF: begin
                    oled_vddc <= 1'b1; oled_vbatc <= 1'b1; oled_res <= 1'b1; oled_on <= 1'b0;
                    in_run <= 1'b0;
                    if (!shutdown) begin
                        step <= 5'd0;
                        start_delay(CYC_MS, M_STEP);        // 1 ms with everything off
                    end
                end

                M_DLY: begin
                    if (dly_cnt == 24'd0) state <= after;
                    else                  dly_cnt <= dly_cnt - 24'd1;
                end

                M_TX: state <= M_TX_WAIT;
                M_TX_WAIT: state <= M_TX_WAIT2;             // let spi_busy rise
                M_TX_WAIT2: if (!spi_busy) state <= after;

                // ---------------- power-up sequence ----------------
                M_STEP: begin
                    step <= step + 5'd1;
                    case (step)
                        5'd0:  begin oled_vddc <= 1'b0; start_delay(2 * CYC_MS, M_STEP); end      // VDD on, >= 1 ms
                        5'd1:  start_tx(1'b0, init_cmd(4'd0), M_STEP);                             // display off
                        5'd2:  begin oled_res <= 1'b0; start_delay(10 * CYC_US, M_STEP); end       // RES low >= 3 us
                        5'd3:  begin oled_res <= 1'b1; start_delay(10 * CYC_US, M_STEP); end
                        5'd4:  start_tx(1'b0, init_cmd(4'd1), M_STEP);                             // charge pump
                        5'd5:  start_tx(1'b0, init_cmd(4'd2), M_STEP);
                        5'd6:  start_tx(1'b0, init_cmd(4'd3), M_STEP);                             // pre-charge
                        5'd7:  start_tx(1'b0, init_cmd(4'd4), M_STEP);
                        5'd8:  begin page <= 2'd0; ret_run <= 1'b0; cmdn <= 2'd0; state <= R_CMD; end  // fill screen RAM first
                        5'd9:  begin oled_vbatc <= 1'b0; start_delay(100 * CYC_MS, M_STEP); end    // VBAT on, 100 ms
                        5'd10: start_tx(1'b0, init_cmd(4'd5), M_STEP);
                        5'd11: start_tx(1'b0, init_cmd(4'd6), M_STEP);
                        5'd12: start_tx(1'b0, init_cmd(4'd7), M_STEP);
                        5'd13: start_tx(1'b0, init_cmd(4'd8), M_STEP);
                        5'd14: start_tx(1'b0, init_cmd(4'd9), M_STEP);                             // display on
                        default: begin
                            oled_on <= 1'b1; in_run <= 1'b1; ret_run <= 1'b1;
                            state <= M_RUN;
                        end
                    endcase
                end

                // ---------------- running: refresh loop, watch for shutdown ----------------
                M_RUN: begin
                    if (shutdown) begin
                        oled_on <= 1'b0; in_run <= 1'b0; step <= 5'd0; state <= M_PD;
                    end else begin
                        page <= 2'd0; cmdn <= 2'd0; state <= R_CMD;
                    end
                end

                // ---------------- power-down sequence ----------------
                M_PD: begin
                    step <= step + 5'd1;
                    case (step)
                        5'd0:  start_tx(1'b0, init_cmd(4'd0), M_PD);                               // display off
                        5'd1:  begin oled_vbatc <= 1'b1; start_delay(100 * CYC_MS, M_PD); end      // VBAT off, 100 ms
                        5'd2:  begin oled_vddc <= 1'b1; start_delay(CYC_MS, M_PD); end             // VDD off
                        default: state <= M_OFF;
                    endcase
                end

                // ---------------- refresh one page at a time ----------------
                R_CMD: begin
                    case (cmdn)
                        2'd0: begin cmdn <= 2'd1; start_tx(1'b0, {6'b101100, page}, R_CMD); end    // 0xB0 + page
                        2'd1: begin cmdn <= 2'd2; start_tx(1'b0, 8'h00, R_CMD); end                // column low
                        default: begin start_tx(1'b0, 8'h10, R_FETCH); n <= 7'd0; end              // column high
                    endcase
                end

                R_FETCH: state <= R_FWAIT;
                R_FWAIT: state <= R_DATA;
                R_DATA:  start_tx(1'b1, in_glyph ? font_data : 8'h00, R_NEXT);

                R_NEXT: begin
                    if (n == 7'd127) begin
                        if (page == 2'd3) begin
                            if (ret_run) state <= M_RUN;
                            else         state <= M_STEP;
                        end else begin
                            page <= page + 2'd1; cmdn <= 2'd0; state <= R_CMD;
                        end
                    end else begin
                        n <= n + 7'd1; state <= R_FETCH;
                    end
                end

                default: state <= M_OFF;
            endcase
        end
    end

endmodule
