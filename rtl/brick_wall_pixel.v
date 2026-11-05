`timescale 1ns / 1ps

// Warm stone, matching the approved 10.1a preview. Coordinates are maze pixels,
// not screen pixels: 16x8 staggered courses turn and pan with the maze. The
// pattern repeats every 64 pixels, so only six coordinate bits are needed.
module brick_wall_pixel (
    input  wire [5:0] maze_x,
    input  wire [5:0] maze_y,
    input  wire gray,
    output reg [11:0] rgb
);
    wire [5:0] shifted_x = maze_x + {2'b00, maze_y[3], 3'b000};
    wire [3:0] brick_x = shifted_x[3:0];
    wire [2:0] brick_y = maze_y[2:0];
    wire [1:0] variant = shifted_x[5:4] ^ maze_y[4:3] ^ maze_y[5:4];

    always @* begin
        case (variant)
            2'd0: rgb = gray ? 12'h777 : 12'h987;
            2'd1: rgb = gray ? 12'h888 : 12'ha98;
            2'd2: rgb = gray ? 12'h778 : 12'h998;
            default: rgb = gray ? 12'h667 : 12'h887;
        endcase
        if (brick_x == 0 || brick_y == 0)
            rgb = gray ? 12'h222 : 12'h433;      // recessed mortar
        else if (brick_x == 15 || brick_y == 7)
            rgb = gray ? 12'h444 : 12'h654;      // lower/right shadow
        else if (brick_y == 1 || brick_x == 1)
            rgb = gray ? 12'haaa : 12'hba8;      // worn upper/left edge
        else if ((brick_y == 3 && (brick_x == 4 || brick_x == 5) && variant != 2) ||
                 (brick_y == 5 && brick_x == 11 && variant == 2))
            rgb = gray ? 12'haaa : 12'hba8;      // sparse chips
        else if (brick_y == 5 && (brick_x == 7 || brick_x == 8) && variant == 1)
            rgb = gray ? 12'h555 : 12'h776;
    end
endmodule
