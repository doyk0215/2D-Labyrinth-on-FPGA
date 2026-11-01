`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// One-bit maze memory, 32 x 32 tiles at addr = {row, col}; the largest stage
// (N=15) uses rows and columns 0..30. The two synchronous read ports serve
// physics and rendering; maze_gen is the sole runtime writer through the write port.
module maze_ram (
    input  wire       clk,
    input  wire       we,
    input  wire [`MAP_ADDR_W-1:0] waddr,
    input  wire       wdata,
    input  wire [`MAP_ADDR_W-1:0] raddr_p,
    output reg        rdata_p,
    input  wire       ren_r,
    input  wire [`MAP_ADDR_W-1:0] raddr_r,
    output reg        rdata_r
);

    localparam [20:0] ROW_WALL         = {21{1'b1}};
    localparam [20:0] ROW_OPEN         = {1'b1, {19{1'b0}}, 1'b1};
    localparam [20:0] ROW_CONNECT_LEFT = {{19{1'b1}}, 1'b0, 1'b1};
    localparam [20:0] ROW_CONNECT_RIGHT = {1'b1, 1'b0, {19{1'b1}}};

    // A deterministic snake corridor through the 10x10 cell area.
    // Bit 0 is tile (row 0, col 0); 1 = wall, 0 = floor.
    localparam [440:0] FIXED_MAP = {
        ROW_WALL,
        ROW_OPEN, ROW_CONNECT_RIGHT,
        ROW_OPEN, ROW_CONNECT_LEFT,
        ROW_OPEN, ROW_CONNECT_RIGHT,
        ROW_OPEN, ROW_CONNECT_LEFT,
        ROW_OPEN, ROW_CONNECT_RIGHT,
        ROW_OPEN, ROW_CONNECT_LEFT,
        ROW_OPEN, ROW_CONNECT_RIGHT,
        ROW_OPEN, ROW_CONNECT_LEFT,
        ROW_OPEN, ROW_CONNECT_RIGHT,
        ROW_OPEN, ROW_WALL
    };

    reg tile_mem [0:`MAP_TILES-1];
    integer init_row, init_col;

    // Vivado carries these constant initial values into the FPGA RAM init.
    // The 21x21 fixed map sits in rows and columns 0..20; the rest is wall.
    initial begin
        rdata_p = 1'b0;
        rdata_r = 1'b0;
        for (init_row = 0; init_row < 32; init_row = init_row + 1)
            for (init_col = 0; init_col < 32; init_col = init_col + 1)
                tile_mem[init_row * `MAP_STRIDE + init_col] =
                    (init_row < 21 && init_col < 21) ? FIXED_MAP[init_row * 21 + init_col] : 1'b1;
    end

    always @(posedge clk) begin
        if (we)
            tile_mem[waddr] <= wdata;
        rdata_p <= tile_mem[raddr_p];
        // Hold the render port during GENERATE so the renderer cannot sample
        // a partially written map (Story 1.4).
        if (ren_r)
            rdata_r <= tile_mem[raddr_r];
    end

endmodule
