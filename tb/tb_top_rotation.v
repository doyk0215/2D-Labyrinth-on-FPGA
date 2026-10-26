`timescale 1ns / 1ps

// Verify the full input -> angle -> ROM -> frame snapshot connection.
module tb_top_rotation;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg btnR = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res;
    wire oled_vbatc, oled_vddc;
    always #5 clk = ~clk;

    top dut (
        .clk(clk), .btnC(rst), .btnU(1'b0), .btnL(1'b0),
        .btnR(btnR), .btnD(1'b0), .sw(16'h0001), .led(led),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk),
        .oled_dc(oled_dc), .oled_res(oled_res),
        .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0; btnR = 1'b1;
        repeat (4) @(posedge clk);
        #1;
        if (led[1:0] !== 2'b01) begin
            $display("FAIL top rotation: right button did not select clockwise");
            $finish;
        end

        wait (dut.frame_tick === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (dut.angle !== 12'd17 || dut.render_i.angle_snap !== 12'd17 ||
            dut.render_i.sin_snap !== dut.trig_i.sin_q ||
            dut.render_i.cos_snap !== dut.trig_i.cos_q) begin
            $display("FAIL top rotation: first frame angle=%0d snapshot=%0d sin=%0d/%0d cos=%0d/%0d",
                     dut.angle, dut.render_i.angle_snap,
                     dut.render_i.sin_snap, dut.trig_i.sin_q,
                     dut.render_i.cos_snap, dut.trig_i.cos_q);
            $finish;
        end

        @(negedge clk); btnR = 1'b0;
        repeat (4) @(posedge clk);
        #1;
        if (led[1:0] !== 2'b00) begin
            $display("FAIL top rotation: release did not stop command");
            $finish;
        end
        wait (dut.frame_tick === 1'b0);
        wait (dut.frame_tick === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (dut.angle !== 12'd17 || dut.render_i.angle_snap !== 12'd17) begin
            $display("FAIL top rotation: angle did not hold after release");
            $finish;
        end

        $display("PASS: top rotation command, angle accumulator, trig and frame snapshot");
        $finish;
    end
endmodule
