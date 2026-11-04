`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// N = 20 maze generation. For many seeds: every one of the 400 cells is
// reached from the start (BFS over the 41 x 41 map) and the goal is reached;
// the stack never exceeds 400 entries; the floor holds the 2N^2 - 1 tiles of
// a spanning tree plus at most K = 6 loop openings; every tile outside the
// 41 x 41 map, up to the 64-tile stride, is wall; the six boxes are valid,
// distinct, on cells that are not the start or goal, and over all seeds some
// sit at quadrant offsets 8..9 (beyond the 0..7 the N <= 15 field allows).
// Out-of-range sizes are clamped: 21..31 build N = 20, 0 and 1 build N = 2.
module tb_n20_maze;
    reg clk = 1'b0, rst = 1'b1, gen_start = 1'b0;
    reg [`N_CELLS_W-1:0] n_cells = 5'd20;
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
    integer i;
    initial for (i = 0; i < `MAP_TILES; i = i + 1) mem[i] = 1'b0;   // stale floor on purpose
    always @(posedge clk) if (we) mem[waddr] <= wdata;

    integer max_sp = 0;
    always @(posedge clk) if (dut.sp > max_sp) max_sp = dut.sp;

    integer errors = 0;
    task fail; input [511:0] msg;
        begin
            errors = errors + 1;
            if (errors <= 10) $display("FAIL N=20 maze: %0s (seed %08h, N in %0d)", msg, seed, n_cells);
        end
    endtask

    task generate_maze;
        integer guard;
        begin
            @(negedge clk) gen_start = 1'b1;
            @(negedge clk) gen_start = 1'b0;
            guard = 0;
            while (!gen_done && guard < 2000000) begin @(negedge clk); guard = guard + 1; end
            if (!gen_done) fail("generation timed out");
            @(negedge clk);
        end
    endtask

    // BFS from the start over floor tiles of an n x n-cell map.
    reg seen [0:`MAP_TILES-1];
    integer queue [0:`MAP_TILES-1];
    integer reached_cells, reached_goal, floor_tiles;
    task check_map;
        input integer n;
        integer head, tail, a, r, c, d, nr, nc, side;
        begin
            side = 2 * n + 1;
            floor_tiles = 0;
            for (r = 0; r < `MAP_STRIDE; r = r + 1)
                for (c = 0; c < `MAP_STRIDE; c = c + 1) begin
                    seen[r * `MAP_STRIDE + c] = 1'b0;
                    if (r < side && c < side) begin
                        if (!mem[r * `MAP_STRIDE + c]) floor_tiles = floor_tiles + 1;
                        if ((r == 0 || c == 0 || r == side - 1 || c == side - 1) && !mem[r * `MAP_STRIDE + c])
                            fail("outer wall has a gap");
                    end else if (!mem[r * `MAP_STRIDE + c])
                        fail("tile outside the active map is not wall");
                end
            if (start_col !== 2 * n - 1 || start_row !== 2 * n - 1) fail("start tile");
            if (goal_col !== 1 || goal_row !== 1) fail("goal tile");
            head = 0; tail = 0; reached_cells = 0; reached_goal = 0;
            a = start_row * `MAP_STRIDE + start_col;
            seen[a] = 1'b1; queue[tail] = a; tail = tail + 1;
            while (head < tail) begin
                a = queue[head]; head = head + 1;
                r = a / `MAP_STRIDE; c = a % `MAP_STRIDE;
                if ((r % 2) == 1 && (c % 2) == 1) reached_cells = reached_cells + 1;
                if (r == 1 && c == 1) reached_goal = 1;
                for (d = 0; d < 4; d = d + 1) begin
                    nr = r + ((d == 0) ? -1 : (d == 2) ? 1 : 0);
                    nc = c + ((d == 1) ? 1 : (d == 3) ? -1 : 0);
                    if (nr >= 0 && nc >= 0 && nr < side && nc < side &&
                        !mem[nr * `MAP_STRIDE + nc] && !seen[nr * `MAP_STRIDE + nc]) begin
                        seen[nr * `MAP_STRIDE + nc] = 1'b1;
                        queue[tail] = nr * `MAP_STRIDE + nc; tail = tail + 1;
                    end
                end
            end
            if (reached_cells != n * n) fail("not every cell is reachable from the start");
            if (!reached_goal) fail("goal not reachable");
            if (floor_tiles < 2 * n * n - 1) fail("fewer floor tiles than a spanning tree");
        end
    endtask

    integer s, k, j, cx, cy, ox, oy, far_offset, loops_seen, loops;
    initial begin
        far_offset = 0; loops_seen = 0;
        repeat (3) @(negedge clk); rst = 1'b0;
        for (s = 0; s < 40; s = s + 1) begin
            n_cells = 5'd20; seed = 32'h9e37_79b9 * (s + 1) ^ 32'h0000_5a5a;
            generate_maze();
            check_map(20);
            loops = floor_tiles - (2 * 20 * 20 - 1);
            if (loops > 6) fail("more than K = 6 loop openings");
            if (loops > loops_seen) loops_seen = loops;
            if (box_valid !== 6'b111111) fail("N = 20 must place six boxes");
            for (k = 0; k < 6; k = k + 1) begin
                cx = box_cols[k * `COORD_W +: `COORD_W];
                cy = box_rows[k * `COORD_W +: `COORD_W];
                if ((cx % 2) != 1 || (cy % 2) != 1 || cx > 39 || cy > 39) fail("box not on a cell of the map");
                if (cx == 39 && cy == 39) fail("box on the start cell");
                if (cx == 1 && cy == 1) fail("box on the goal cell");
                if (mem[cy * `MAP_STRIDE + cx]) fail("box on a wall");
                for (j = 0; j < k; j = j + 1)
                    if (box_cols[j * `COORD_W +: `COORD_W] == cx && box_rows[j * `COORD_W +: `COORD_W] == cy)
                        fail("two boxes share a cell");
                ox = ((cx - 1) / 2) % 10; oy = ((cy - 1) / 2) % 10;
                if (ox >= 8 || oy >= 8) far_offset = far_offset + 1;
            end
        end
        if (max_sp > 400) fail("stack exceeded 400 entries");
        if (far_offset == 0) fail("no box at quadrant offset 8..9 in 40 seeds");
        if (loops_seen == 0) fail("no loop opening in 40 seeds");

        // Clamp: 21..31 build N = 20; 0 and 1 build N = 2.
        n_cells = 5'd31; seed = 32'h0bad_cafe; generate_maze(); check_map(20);
        n_cells = 5'd21; seed = 32'h0000_0021; generate_maze(); check_map(20);
        n_cells = 5'd0;  seed = 32'h0000_0001; generate_maze(); check_map(2);
        n_cells = 5'd1;  seed = 32'h0000_0002; generate_maze(); check_map(2);

        if (errors == 0)
            $display("PASS: N=20 maze_gen 40 seeds connected and solvable, stack max %0d, loops up to %0d, six boxes (%0d at quadrant offset 8..9), walls outside 41x41, clamp 0/1/21/31",
                     max_sp, loops_seen, far_offset);
        else
            $display("FAIL N=20 maze: %0d errors", errors);
        $finish;
    end
endmodule
