`timescale 1ns / 1ps

module tb_render;

    reg clk = 1'b0;
    reg rst = 1'b1;
    wire [15:0] led;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire vga_hs;
    wire vga_vs;
    wire ps2_clk;
    wire ps2_data;
    wire oled_cs;
    wire oled_mosi;
    wire oled_sclk;
    wire oled_dc;
    wire oled_res;
    wire oled_vbatc;
    wire oled_vddc;

    always #5 clk = ~clk;

    top dut (
        .clk        (clk),
        .btnC       (rst),
        .btnU       (1'b0),
        .btnL       (1'b0),
        .btnR       (1'b0),
        .btnD       (1'b0),
        .sw         (16'h0000),
        .led        (led),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .vga_hs     (vga_hs),
        .vga_vs     (vga_vs),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
        .oled_cs    (oled_cs),
        .oled_mosi  (oled_mosi),
        .oled_sclk  (oled_sclk),
        .oled_dc    (oled_dc),
        .oled_res   (oled_res),
        .oled_vbatc (oled_vbatc),
        .oled_vddc  (oled_vddc)
    );

    task check_pixel;
        input [9:0] target_x;
        input [9:0] target_y;
        input [11:0] expected_rgb;
        begin
            while ((dut.timing_i.pixel_x !== target_x) ||
                   (dut.timing_i.pixel_y !== target_y))
                @(negedge clk);
            // Allow the synchronous maze RAM read and renderer pipeline to settle.
            @(posedge clk);
            #1;
            if ({vga_r, vga_g, vga_b} !== expected_rgb) begin
                $display("FAIL: pixel (%0d,%0d) RGB=%h expected=%h",
                         target_x, target_y, {vga_r, vga_g, vga_b}, expected_rgb);
                $finish;
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Screen map bounds are x=152..487 and y=72..407.
        check_pixel(10'd160, 10'd80,  12'hfff); // outer wall
        check_pixel(10'd151, 10'd96,  12'h002); // background left of maze
        check_pixel(10'd176, 10'd96,  12'h0f0); // start tile (col 1, row 1)
        check_pixel(10'd192, 10'd96,  12'h346); // ordinary floor
        check_pixel(10'd176, 10'd112, 12'hfff); // internal wall
        check_pixel(10'd464, 10'd112, 12'h346); // snake corridor floor
        check_pixel(10'd176, 10'd384, 12'hf00); // goal tile (col 1, row 19)
        check_pixel(10'd320, 10'd408, 12'h002); // background below maze

        $display("PASS: fixed maze wall, floor, start, goal, centering, and background pixels");
        $finish;
    end

endmodule
