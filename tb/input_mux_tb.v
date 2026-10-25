`timescale 1ns/1ps

module input_mux_tb;
    reg mouse_connected;
    reg mouse_left;
    reg mouse_right;
    reg btn_left;
    reg btn_right;
    wire signed [1:0] rot_cmd;

    input_mux dut (
        .mouse_connected(mouse_connected),
        .mouse_left(mouse_left),
        .mouse_right(mouse_right),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .rot_cmd(rot_cmd)
    );

    task check_cmd;
        input signed [1:0] expected;
        input [255:0] label_text;
        begin
            #1;
            if (rot_cmd !== expected) begin
                $display("FAIL input_mux: %0s expected %0d got %0d", label_text, expected, rot_cmd);
                $finish;
            end
        end
    endtask

    initial begin
        mouse_connected = 1'b1;
        mouse_left = 1'b1; mouse_right = 1'b0;
        btn_left = 1'b0; btn_right = 1'b1;
        check_cmd(-2'sd1, "mouse left overrides fallback");

        mouse_left = 1'b0; mouse_right = 1'b1;
        check_cmd(2'sd1, "mouse right");
        mouse_left = 1'b1; mouse_right = 1'b1;
        check_cmd(2'sd0, "mouse both");
        mouse_left = 1'b0; mouse_right = 1'b0;
        check_cmd(2'sd0, "mouse neither");

        mouse_connected = 1'b0;
        btn_left = 1'b1; btn_right = 1'b0;
        check_cmd(-2'sd1, "fallback left");
        btn_left = 1'b0; btn_right = 1'b1;
        check_cmd(2'sd1, "fallback right");
        btn_left = 1'b1; btn_right = 1'b1;
        check_cmd(2'sd0, "fallback both");
        btn_left = 1'b0; btn_right = 1'b0;
        check_cmd(2'sd0, "fallback neither");

        $display("PASS input_mux_tb");
        $finish;
    end
endmodule
