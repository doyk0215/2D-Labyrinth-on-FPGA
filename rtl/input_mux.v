`timescale 1ns/1ps

// Select mouse controls when a valid stream is present; otherwise use buttons.
module input_mux (
    input  wire mouse_connected,
    input  wire mouse_left,
    input  wire mouse_right,
    input  wire btn_left,
    input  wire btn_right,
    output reg signed [1:0] rot_cmd
);
    reg selected_left;
    reg selected_right;

    always @* begin
        if (mouse_connected) begin
            selected_left  = mouse_left;
            selected_right = mouse_right;
        end else begin
            selected_left  = btn_left;
            selected_right = btn_right;
        end

        if (selected_left && !selected_right)
            rot_cmd = -2'sd1;
        else if (selected_right && !selected_left)
            rot_cmd = 2'sd1;
        else
            rot_cmd = 2'sd0;
    end
endmodule
