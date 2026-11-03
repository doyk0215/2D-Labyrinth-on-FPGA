`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// N <= 15 must not change when the map format widens for N = 20. For every
// N from 2 to 15 and 16 seeds, a CRC of the active map, start, goal and the
// six box slots must equal the value captured on main 3fdc74d (before the
// widening). The bench uses only the package macros, so it ran unchanged on
// both versions. CAPTURE=1 prints the table instead of checking it.
// The CUSTOM stage gave N = 4 (no boxes) and N = 8, 9, 11..14 (loops) new
// rules on purpose; those sizes are not compared here (tb_custom_stage checks
// their structure), every other N must still match main.
module tb_maze_gen_golden #(parameter CAPTURE = 0);
    reg clk = 1'b0, rst = 1'b1, gen_start = 1'b0;
    reg [`N_CELLS_W-1:0] n_cells = 0;
    reg [31:0] seed = 32'd1;
    wire gen_busy, gen_done, we, wdata;
    wire [`MAP_ADDR_W-1:0] waddr;
    wire [`COORD_W-1:0] start_col, start_row, goal_col, goal_row;
    wire [6*`COORD_W-1:0] box_cols, box_rows;
    wire [5:0] box_valid;
    always #5 clk = ~clk;

    maze_gen dut (
        .clk(clk), .rst(rst), .gen_start(gen_start), .n_cells(n_cells), .seed(seed),
        .gen_busy(gen_busy), .gen_done(gen_done), .we(we), .waddr(waddr), .wdata(wdata),
        .start_col(start_col), .start_row(start_row), .goal_col(goal_col), .goal_row(goal_row),
        .box_cols(box_cols), .box_rows(box_rows), .box_valid(box_valid)
    );

    reg mem [0:`MAP_TILES-1];
    always @(posedge clk) if (we) mem[waddr] <= wdata;

    reg [31:0] crc;
    task add_bits; input integer value; input integer bits;
        integer b;
        begin
            for (b = bits - 1; b >= 0; b = b - 1)
                crc = {crc[30:0], 1'b0} ^ ((crc[31] ^ ((value >> b) & 1)) ? 32'h04C11DB7 : 32'h0);
        end
    endtask

    `include "tb_maze_gen_golden.vh"   // expected[0:223]: index (n-2)*16 + s

    function new_rule; input integer n;
        begin new_rule = (n == 4) || (n == 8) || (n == 9) || (n >= 11 && n <= 14); end
    endfunction

    integer n, s, r, c, k, guard, failures;
    initial begin
        failures = 0;
        repeat (3) @(negedge clk); rst = 1'b0;
        for (n = 2; n <= 15; n = n + 1)
            for (s = 0; s < 16; s = s + 1) begin
                n_cells = n; seed = 32'h1234_5678 * (s + 1) + n;
                @(negedge clk) gen_start = 1'b1;
                @(negedge clk) gen_start = 1'b0;
                guard = 0;
                while (!gen_done && guard < 400000) begin @(negedge clk); guard = guard + 1; end
                if (!gen_done) begin $display("FAIL maze_gen golden: N=%0d seed %0d timeout", n, s); $finish; end
                @(negedge clk);
                crc = 32'hffff_ffff;
                for (r = 0; r <= 2 * n; r = r + 1)
                    for (c = 0; c <= 2 * n; c = c + 1)
                        add_bits(mem[r * `MAP_STRIDE + c], 1);
                add_bits(start_col, 5); add_bits(start_row, 5);
                add_bits(goal_col, 5); add_bits(goal_row, 5);
                for (k = 0; k < 6; k = k + 1) begin
                    add_bits(box_valid[k], 1);
                    add_bits(box_cols[k * `COORD_W +: `COORD_W], 5);
                    add_bits(box_rows[k * `COORD_W +: `COORD_W], 5);
                end
                if (CAPTURE)
                    $display("    expected[%0d] = 32'h%08h;", (n - 2) * 16 + s, crc);
                else if (!new_rule(n) && crc !== expected[(n - 2) * 16 + s]) begin
                    $display("FAIL maze_gen golden: N=%0d seed %0d crc %08h expected %08h",
                             n, s, crc, expected[(n - 2) * 16 + s]);
                    failures = failures + 1;
                end
            end
        if (!CAPTURE && failures == 0)
            $display("PASS: maze_gen golden N=2,3,5,6,7,10,15, 16 seeds each, map/start/goal/boxes identical to main 3fdc74d");
        $finish;
    end
endmodule
