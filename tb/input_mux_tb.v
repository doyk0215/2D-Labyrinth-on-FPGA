`timescale 1ns/1ps

// input_mux: either source rotates; both or neither = no rotation.
module input_mux_tb;
    reg mouse_left;
    reg mouse_right;
    reg btn_left;
    reg btn_right;
    wire signed [1:0] rot_cmd;

    input_mux dut (
        .mouse_left(mouse_left),
        .mouse_right(mouse_right),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .rot_cmd(rot_cmd)
    );

    task check_cmd;
        input ml, mr, bl, br;
        input signed [1:0] expected;
        input [255:0] label_text;
        begin
            mouse_left = ml; mouse_right = mr; btn_left = bl; btn_right = br;
            #1;
            if (rot_cmd !== expected) begin
                $display("FAIL input_mux: %0s expected %0d got %0d", label_text, expected, rot_cmd);
                $finish;
            end
        end
    endtask

    integer i;
    initial begin
        // mouse only
        check_cmd(1, 0, 0, 0, -2'sd1, "mouse left");
        check_cmd(0, 1, 0, 0,  2'sd1, "mouse right");
        check_cmd(1, 1, 0, 0,  2'sd0, "mouse both");
        // board buttons only (no mouse, or mouse idle)
        check_cmd(0, 0, 1, 0, -2'sd1, "btnL");
        check_cmd(0, 0, 0, 1,  2'sd1, "btnR");
        check_cmd(0, 0, 1, 1,  2'sd0, "btnL and btnR");
        // both sources on the same side
        check_cmd(1, 0, 1, 0, -2'sd1, "mouse left and btnL");
        check_cmd(0, 1, 0, 1,  2'sd1, "mouse right and btnR");
        // opposite sides cancel
        check_cmd(1, 0, 0, 1,  2'sd0, "mouse left and btnR");
        check_cmd(0, 1, 1, 0,  2'sd0, "mouse right and btnL");
        check_cmd(0, 0, 0, 0,  2'sd0, "nothing pressed");

        // Hold still: the mouse button stays latched with no packets; the
        // command must stay -1 for as long as the button is held.
        check_cmd(1, 0, 0, 0, -2'sd1, "hold start");
        for (i = 0; i < 1000; i = i + 1) begin
            #1000;
            if (rot_cmd !== -2'sd1) begin
                $display("FAIL input_mux: held mouse button dropped at step %0d", i);
                $finish;
            end
        end

        $display("PASS input_mux_tb");
        $finish;
    end
endmodule
