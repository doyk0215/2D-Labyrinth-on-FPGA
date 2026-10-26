`timescale 1ns / 1ps

// seed_source: picks the seed for maze_gen (Story 1.3, FR3).
//   debug_fixed = 1 : a fixed seed, so a maze can be reproduced.
//   debug_fixed = 0 : a free-running counter captured on each generation
//                     request (latch_en pulse), then held for that run.
// Repeated captures let Story 1.4 produce a fresh seed on regeneration.
module seed_source (
    input  wire        clk,
    input  wire        rst,
    input  wire        debug_fixed,
    input  wire        latch_en,      // one-cycle pulse for each generation
    output wire [31:0] seed
);

    localparam [31:0] FIXED_SEED = 32'hC0FFEE01;

    reg [31:0] counter;
    reg [31:0] latched;
    reg        have_latch;

    always @(posedge clk) begin
        if (rst) begin
            counter    <= 32'd1;
            have_latch <= 1'b0;
        end else begin
            counter <= counter + 32'd1;
            if (latch_en) begin
                latched    <= counter;
                have_latch <= 1'b1;
            end
        end
    end

    assign seed = debug_fixed ? FIXED_SEED : (have_latch ? latched : counter);

endmodule
