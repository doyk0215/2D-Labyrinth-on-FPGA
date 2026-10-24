`timescale 1ns / 1ps

// oled_spi: sends one byte to the SSD1306 over SPI mode 0 (CPOL=0, CPHA=0),
// MSB first. SCLK = clk / 16 (6.25 MHz at 100 MHz, within the 10 MHz limit).
// CS is held low for the whole byte; D/C is set before CS falls and held.
//   start (1-clk pulse, only when !busy) -> busy until the byte is done.
module oled_spi (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       dc_in,       // 0 = command, 1 = display data
    input  wire [7:0] data,
    output reg        busy,
    output reg        cs_n,
    output reg        sclk,
    output reg        mosi,
    output reg        dc
);

    localparam [2:0] IDLE = 3'd0, HEAD = 3'd1, BITS = 3'd2, TAIL = 3'd3, GAP = 3'd4;

    reg [2:0] st;
    reg [3:0] cnt;
    reg [2:0] bitn;
    reg [7:0] sh;

    always @(posedge clk) begin
        if (rst) begin
            st <= IDLE; busy <= 1'b0; cs_n <= 1'b1; sclk <= 1'b0; mosi <= 1'b0; dc <= 1'b0;
            cnt <= 4'd0; bitn <= 3'd0; sh <= 8'd0;
        end else begin
            case (st)
                IDLE: begin
                    cs_n <= 1'b1; sclk <= 1'b0; busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; dc <= dc_in; sh <= data;
                        cs_n <= 1'b0; cnt <= 4'd0; st <= HEAD;
                    end
                end
                HEAD: begin                          // CS low, SCLK low: set-up time
                    cnt <= cnt + 4'd1;
                    if (cnt == 4'd7) begin
                        cnt <= 4'd0; bitn <= 3'd0; mosi <= sh[7]; st <= BITS;
                    end
                end
                BITS: begin                          // 16 clocks per bit, SCLK high in the second half
                    cnt <= cnt + 4'd1;
                    if (cnt == 4'd7) sclk <= 1'b1;
                    if (cnt == 4'd15) begin
                        sclk <= 1'b0; cnt <= 4'd0;
                        if (bitn == 3'd7) st <= TAIL;
                        else begin
                            bitn <= bitn + 3'd1;
                            sh   <= {sh[6:0], 1'b0};
                            mosi <= sh[6];
                        end
                    end
                end
                TAIL: begin                          // CS stays low briefly after the last bit
                    cnt <= cnt + 4'd1;
                    if (cnt == 4'd7) begin cs_n <= 1'b1; cnt <= 4'd0; st <= GAP; end
                end
                GAP: begin                           // CS high gap between bytes
                    cnt <= cnt + 4'd1;
                    if (cnt == 4'd7) begin st <= IDLE; busy <= 1'b0; end
                end
                default: st <= IDLE;
            endcase
        end
    end

endmodule
