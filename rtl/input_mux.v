`timescale 1ns/1ps

// Rotation command from the mouse buttons and the board buttons together.
// Either source can rotate the maze: left = mouse left OR btnL, right = mouse
// right OR btnR. Left only = -1 (counter-clockwise), right only = +1
// (clockwise), both or neither = 0.
//
// There is deliberately no "mouse connected" switch: a PS/2 mouse in stream
// mode only sends a packet when it moves or a button changes, so a button held
// still produces no packets, and a packet timeout would wrongly drop the held
// button. MouseCtl keeps its button outputs at 0 until a mouse is initialised
// and clears them when its presence check finds the mouse gone.
module input_mux (
    input  wire mouse_left,
    input  wire mouse_right,
    input  wire btn_left,
    input  wire btn_right,
    output reg signed [1:0] rot_cmd
);
    wire left  = mouse_left  | btn_left;
    wire right = mouse_right | btn_right;

    always @* begin
        if (left && !right)
            rot_cmd = -2'sd1;
        else if (right && !left)
            rot_cmd = 2'sd1;
        else
            rot_cmd = 2'sd0;
    end
endmodule
