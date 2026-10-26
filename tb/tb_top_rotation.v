`timescale 1ns / 1ps

// Verify the full input -> angle -> ROM -> frame snapshot connection.
module tb_top_rotation;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg btnR = 1'b0;
    reg [15:0] sw = 16'h0001;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res;
    wire oled_vbatc, oled_vddc;
    always #5 clk = ~clk;

    top #(.SNAP_DEBOUNCE_CYCLES(3)) dut (
        .clk(clk), .btnC(rst), .btnU(1'b0), .btnL(1'b0),
        .btnR(btnR), .btnD(1'b0), .sw(sw), .led(led),
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

        // SW5 selects the fallback. A complete board-button press moves the
        // same angle/sine/cosine pipeline to the next quadrant on a frame.
        @(negedge clk); sw[5] = 1'b1;
        repeat (4) @(negedge clk);
        // A short board-button bounce is ignored by the snap-only debouncer.
        btnR = 1'b1;
        @(negedge clk); btnR = 1'b0;
        repeat (6) @(negedge clk);
        if (dut.btnR_snap !== 1'b0 || dut.angle_i.pending_valid !== 1'b0) begin
            $display("FAIL top rotation: button bounce queued a snap");
            $finish;
        end
        btnR = 1'b1;
        repeat (8) @(negedge clk);
        if (dut.angle !== 12'd17) begin
            $display("FAIL top rotation: snap mode moved before release");
            $finish;
        end
        btnR = 1'b0;
        @(negedge clk); btnR = 1'b1;
        @(negedge clk); btnR = 1'b0;
        repeat (8) @(negedge clk);
        wait (dut.frame_tick === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (dut.angle !== 12'd1024 || dut.render_i.angle_snap !== 12'd1024 ||
            dut.render_i.sin_snap !== dut.trig_i.sin_q ||
            dut.render_i.cos_snap !== dut.trig_i.cos_q) begin
            $display("FAIL top rotation: SW5 snap did not reach 90 degrees");
            $finish;
        end

        // Returning to smooth mode continues from 90 degrees.
        @(negedge clk); sw[5] = 1'b0; btnR = 1'b1;
        repeat (8) @(negedge clk);
        wait (dut.frame_tick === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (dut.angle !== 12'd1041 || dut.render_i.angle_snap !== 12'd1041) begin
            $display("FAIL top rotation: smooth mode did not resume from snap angle");
            $finish;
        end

        // A stationary mouse hold outlasts mouse_connected's packet timeout.
        // Snap mode must wait for the actual button release.
        @(negedge clk); btnR = 1'b0;
        repeat (8) @(negedge clk);
        sw[5] = 1'b1;
        repeat (4) @(negedge clk);
        force dut.mouse_right = 1'b1;
        force dut.mouse_connected = 1'b1;
        repeat (4) @(negedge clk);
        force dut.mouse_connected = 1'b0;
        repeat (4) @(negedge clk);
        if (dut.rot_held !== 1'b1 || dut.angle_rot_cmd !== 2'sd1 ||
            dut.angle_i.pending_valid !== 1'b0) begin
            $display("FAIL top rotation: mouse packet timeout ended snap hold");
            $finish;
        end
        force dut.mouse_right = 1'b0;
        repeat (3) @(negedge clk);
        if (dut.angle_i.pending_valid !== 1'b1 || dut.angle_i.pending_angle !== 12'd2048) begin
            $display("FAIL top rotation: mouse release did not queue snap");
            $finish;
        end
        // Complete a second mouse click before the next VGA frame.
        force dut.mouse_right = 1'b1;
        repeat (3) @(negedge clk);
        force dut.mouse_right = 1'b0;
        repeat (3) @(negedge clk);
        if (dut.angle !== 12'd1041 || dut.angle_i.pending_angle !== 12'd3072) begin
            $display("FAIL top rotation: two mouse clicks did not accumulate before frame");
            $finish;
        end
        wait (dut.frame_tick === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (dut.angle !== 12'd3072 || dut.render_i.angle_snap !== 12'd3072) begin
            $display("FAIL top rotation: two mouse clicks did not reach 270 degrees");
            $finish;
        end
        release dut.mouse_right;
        release dut.mouse_connected;

        $display("PASS: top rotation command, smooth/snap modes, mouse hold, trig and frame snapshot");
        $finish;
    end
endmodule
