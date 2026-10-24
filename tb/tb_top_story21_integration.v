`timescale 1ns/1ps

module tb_top_story21_integration;
    reg clk = 1'b0;
    reg btnC = 1'b1;
    reg btnU = 1'b0;
    reg btnL = 1'b0;
    reg btnR = 1'b0;
    reg btnD = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire vga_hs;
    wire vga_vs;
    tri ps2_clk;
    tri ps2_data;
    wire oled_cs;
    wire oled_mosi;
    wire oled_sclk;
    wire oled_dc;
    wire oled_res;
    wire oled_vbatc;
    wire oled_vddc;

    pullup ps2_clk_pullup (ps2_clk);
    pullup ps2_data_pullup (ps2_data);

    always #5 clk = ~clk;

    top dut (
        .clk(clk),
        .btnC(btnC),
        .btnU(btnU),
        .btnL(btnL),
        .btnR(btnR),
        .btnD(btnD),
        .sw(16'd0),
        .led(led),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .oled_cs(oled_cs),
        .oled_mosi(oled_mosi),
        .oled_sclk(oled_sclk),
        .oled_dc(oled_dc),
        .oled_res(oled_res),
        .oled_vbatc(oled_vbatc),
        .oled_vddc(oled_vddc)
    );

    task check_rotation_leds;
        input [1:0] expected;
        begin
            repeat (4) @(posedge clk);
            #1;
            if (led[1:0] !== expected) begin
                $display("FAIL: expected rot_cmd LEDs %b, got %b", expected, led[1:0]);
                $finish;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        #1 btnC = 1'b0;
        repeat (4) @(posedge clk);
        #1;
        if (ps2_clk !== 1'b1 || ps2_data !== 1'b1) begin
            $display("FAIL: PS/2 lines were not released while idle");
            $finish;
        end

        // With no valid mouse packet yet, synchronized board buttons control rotation.
        #1 btnL = 1'b1;
        check_rotation_leds(2'b11);
        #1 btnL = 1'b0;
        btnR = 1'b1;
        check_rotation_leds(2'b01);
        #1 btnL = 1'b1;
        check_rotation_leds(2'b00);
        #1 btnL = 1'b0;
        btnR = 1'b0;
        check_rotation_leds(2'b00);

        // Startup inhibit must pull both open-drain lines low, never high.
        repeat (10020) @(posedge clk);
        #1;
        if (ps2_clk !== 1'b0 || ps2_data !== 1'b0) begin
            $display("FAIL: PS/2 startup did not pull both lines low");
            $finish;
        end
        if (dut.mouse_connected !== 1'b0) begin
            $display("FAIL: mouse connected without a valid packet");
            $finish;
        end

        $display("PASS top Story 2.1 integration: fallback controls, LEDs, and open-drain startup");
        $finish;
    end
endmodule
