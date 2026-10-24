`timescale 1ns/1ps

module ps2_mouse_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    tri1 ps2_clk;
    tri1 ps2_data;
    reg device_clk_low = 1'b0;
    reg device_data_low = 1'b0;
    wire dut_clk_low;
    wire dut_data_low;
    wire left_button;
    wire right_button;
    wire connected;
    reg [10:0] host_frame;
    integer k;

    always #5 clk = ~clk;
    assign ps2_clk = device_clk_low ? 1'b0 : 1'bz;
    assign ps2_data = device_data_low ? 1'b0 : 1'bz;
    assign ps2_clk = dut_clk_low ? 1'b0 : 1'bz;
    assign ps2_data = dut_data_low ? 1'b0 : 1'bz;

    ps2_mouse #(.CLK_HZ(1000), .PS2_TIMEOUT_CYCLES(2000)) dut (
        .clk(clk), .rst(rst),
        .ps2_clk_i(ps2_clk), .ps2_data_i(ps2_data),
        .ps2_clk_drive_low(dut_clk_low),
        .ps2_data_drive_low(dut_data_low),
        .left_button(left_button), .right_button(right_button),
        .connected(connected)
    );

    task settle;
        input integer cycles;
        integer n;
        begin
            for (n = 0; n < cycles; n = n + 1) @(posedge clk);
        end
    endtask

    task ps2_pulse;
        begin
            device_clk_low = 1'b1;
            settle(8);
            device_clk_low = 1'b0;
            settle(8);
        end
    endtask

    task send_device_byte;
        input [7:0] data_byte;
        integer b;
        reg parity_bit;
        begin
            parity_bit = ~(^data_byte); // odd parity
            device_data_low = 1'b1; // start bit = 0
            ps2_pulse;
            for (b = 0; b < 8; b = b + 1) begin
                device_data_low = ~data_byte[b];
                ps2_pulse;
            end
            device_data_low = ~parity_bit;
            ps2_pulse;
            device_data_low = 1'b0; // stop bit = 1
            ps2_pulse;
            device_data_low = 1'b0;
        end
    endtask

    task send_packet;
        input [7:0] buttons;
        begin
            send_device_byte(buttons | 8'h08); // bit 3 identifies packet start
            send_device_byte(8'h00);
            send_device_byte(8'h00);
            settle(8);
        end
    endtask

    task expect_buttons;
        input expected_left;
        input expected_right;
        input [127:0] label_text;
        begin
            if (!connected || left_button !== expected_left || right_button !== expected_right) begin
                $display("FAIL ps2_mouse: %0s connected=%b left=%b right=%b", label_text, connected, left_button, right_button);
                $finish;
            end
        end
    endtask

    initial begin
        settle(5);
        rst = 1'b0;

        // Wait for the DUT's request-to-send sequence and then clock the
        // host's 11-bit F4 frame. Sample the data line once per rising edge.
        wait (dut_clk_low && dut_data_low);
        wait (!dut_clk_low && dut_data_low);
        host_frame = 11'd0;
        for (k = 0; k < 11; k = k + 1) begin
            device_clk_low = 1'b1;
            settle(8);
            device_clk_low = 1'b0;
            settle(8);
            host_frame[k] = ps2_data;
        end
        if (host_frame[0] !== 1'b0 || host_frame[8:1] !== 8'hF4 ||
            host_frame[9] !== 1'b0 || host_frame[10] !== 1'b1) begin
            $display("FAIL ps2_mouse: host frame was not F4 with valid framing: %b", host_frame);
            $finish;
        end

        // Device acknowledgement bit (low), followed by a recorded stream.
        device_data_low = 1'b1;
        ps2_pulse;
        device_data_low = 1'b0;
        settle(8);
        send_packet(8'h01); // left only
        expect_buttons(1'b1, 1'b0, "left only");
        send_packet(8'h02); // right only
        expect_buttons(1'b0, 1'b1, "right only");
        send_packet(8'h03); // both
        expect_buttons(1'b1, 1'b1, "both buttons");
        send_packet(8'h00); // neither
        expect_buttons(1'b0, 1'b0, "no buttons");

        $display("PASS ps2_mouse_tb");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL ps2_mouse_tb: timeout");
        $finish;
    end
endmodule
