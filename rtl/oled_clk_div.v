`timescale 1ns / 1ps

// oled_clk_div: 100 MHz / 16 = 6.25 MHz for the course-supplied Oled_Display,
// which needs a real 6.25 MHz clock (it uses clk itself as SCLK). This is the
// single, documented exception to AD-2: a derived clock confined to the OLED
// island. The XDC declares it with create_generated_clock.
module oled_clk_div (
    input  wire clk,
    output wire clk_6m25
);

    reg [3:0] oled_div_cnt = 4'd0;
    always @(posedge clk) oled_div_cnt <= oled_div_cnt + 4'd1;

    BUFG clk_6m25_buf (.I(oled_div_cnt[3]), .O(clk_6m25));

endmodule
