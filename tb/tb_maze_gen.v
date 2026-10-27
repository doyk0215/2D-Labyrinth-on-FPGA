`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for maze_gen and seed_source (Story 1.3).
// For many seeds and sizes it checks: done pulse, start/goal tiles, outer
// walls, nothing outside the maze region, BFS from start to goal, a perfect
// maze (connected + exactly 2N^2-1 floor tiles), determinism per seed, and
// that different seeds give different mazes.
module tb_maze_gen;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         gen_start = 1'b0;
    reg  [3:0]  n_cells = 4'd10;
    reg  [31:0] seed = 32'd1;
    wire        gen_busy, gen_done, we, wdata;
    wire [8:0]  waddr;
    wire [4:0]  start_col, start_row, goal_col, goal_row;

    always #5 clk = ~clk;

    maze_gen dut (
        .clk(clk), .rst(rst), .gen_start(gen_start), .n_cells(n_cells), .seed(seed),
        .gen_busy(gen_busy), .gen_done(gen_done), .we(we), .waddr(waddr), .wdata(wdata),
        .start_col(start_col), .start_row(start_row), .goal_col(goal_col), .goal_row(goal_row)
    );

    // ---- behavioural maze_ram (441 tiles, 1 = wall) ----
    reg mem [0:`MAP_TILES-1];
    integer i;
    initial for (i = 0; i < `MAP_TILES; i = i + 1) mem[i] = 1'b0;   // stale floor on purpose
    always @(posedge clk) if (we) mem[waddr] <= wdata;

    // ---- bookkeeping ----
    integer errors;
    integer runs;
    integer cycles, max_cycles;
    integer done_pulses;
    always @(posedge clk) if (gen_done) done_pulses <= done_pulses + 1;

    // ---- BFS over floor tiles ----
    reg      seen [0:`MAP_TILES-1];
    integer  queue [0:`MAP_TILES-1];
    integer  qh, qt, floor_total, reached, cur, c, r, nb;
    reg      goal_reached;

    task bfs_check;
        input integer N;
        input integer sc, sr, gc, gr;
        integer k;
        begin
            floor_total = 0;
            for (k = 0; k < `MAP_TILES; k = k + 1) begin
                seen[k] = 1'b0;
                if (!mem[k]) floor_total = floor_total + 1;
            end
            qh = 0; qt = 0; reached = 0; goal_reached = 1'b0;
            queue[qt] = sr * 21 + sc; qt = qt + 1; seen[sr * 21 + sc] = 1'b1;
            while (qh < qt) begin
                cur = queue[qh]; qh = qh + 1;
                reached = reached + 1;
                c = cur % 21; r = cur / 21;
                if (c == gc && r == gr) goal_reached = 1'b1;
                if (r > 0)  begin nb = cur - 21; if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (r < 20) begin nb = cur + 21; if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (c > 0)  begin nb = cur - 1;  if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (c < 20) begin nb = cur + 1;  if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
            end
        end
    endtask

    // ---- hash of the memory image ----
    function [63:0] mem_hash;
        input dummy;
        integer k;
        reg [63:0] h;
        begin
            h = 64'hCBF29CE484222325;
            for (k = 0; k < `MAP_TILES; k = k + 1)
                h = (h ^ {63'd0, mem[k]}) * 64'h100000001B3;
            mem_hash = h;
        end
    endfunction

    // ---- one generation run, then all checks ----
    reg [63:0] last_hash;
    task run_gen;
        input integer N;
        input [31:0] s;
        begin run_gen2(N, N, s); end
    endtask

    // N = expected size, drive = value put on n_cells (differs only for the clamp test)
    task run_gen2;
        input integer N;
        input integer drive;
        input [31:0] s;
        integer limit, k, outside_floor, perimeter_floor, off;
        begin
            n_cells = drive[3:0]; seed = s; off = 10 - N;
            @(negedge clk); gen_start = 1'b1;
            @(negedge clk); gen_start = 1'b0;
            cycles = 0; limit = 20000;
            while (!gen_done && cycles < limit) begin @(posedge clk); cycles = cycles + 1; end
            @(negedge clk);
            if (cycles >= limit) begin
                errors = errors + 1; $display("FAIL N=%0d seed=%h: timeout", N, s);
            end else begin
                if (cycles > max_cycles) max_cycles = cycles;
                if (gen_busy) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: busy after done", N, s); end

                // start/goal tiles: start bottom-right, goal top-left
                if (start_col !== (off + 2 * N - 1) || start_row !== (off + 2 * N - 1) ||
                    goal_col !== (off + 1) || goal_row !== (off + 1)) begin
                    errors = errors + 1;
                    $display("FAIL N=%0d seed=%h: start (%0d,%0d) goal (%0d,%0d)", N, s,
                             start_col, start_row, goal_col, goal_row);
                end
                if (mem[start_row * 21 + start_col] || mem[goal_row * 21 + goal_col]) begin
                    errors = errors + 1; $display("FAIL N=%0d seed=%h: start or goal is a wall", N, s);
                end

                // nothing outside the maze region (tiles beyond 2N) and an intact outer wall
                outside_floor = 0; perimeter_floor = 0;
                for (k = 0; k < `MAP_TILES; k = k + 1) begin
                    c = k % 21; r = k / 21;
                    if ((c < off || c > off + 2 * N || r < off || r > off + 2 * N) && !mem[k])
                        outside_floor = outside_floor + 1;
                    if ((c == off || r == off || c == off + 2 * N || r == off + 2 * N) &&
                        c >= off && c <= off + 2 * N && r >= off && r <= off + 2 * N && !mem[k])
                        perimeter_floor = perimeter_floor + 1;
                end
                if (outside_floor != 0) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: %0d floor tiles outside the centred region", N, s, outside_floor); end
                if (perimeter_floor != 0) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: gap in outer wall", N, s); end

                // BFS: goal reachable; connected; perfect maze (tree): 2N^2-1 floor tiles
                bfs_check(N, start_col, start_row, goal_col, goal_row);
                if (!goal_reached) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: goal not reachable", N, s); end
                if (reached != floor_total) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: %0d of %0d floor tiles reachable", N, s, reached, floor_total); end
                if (floor_total != 2 * N * N - 1) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: %0d floor tiles, expected %0d (not a perfect maze)", N, s, floor_total, 2 * N * N - 1); end

                last_hash = mem_hash(1'b0);
                runs = runs + 1;
            end
        end
    endtask

    // ---- seed_source checks ----
    reg         ss_rst = 1'b1, ss_dbg = 1'b0, ss_latch = 1'b0;
    wire [31:0] ss_seed;
    seed_source ss (.clk(clk), .rst(ss_rst), .debug_fixed(ss_dbg), .latch_en(ss_latch), .seed(ss_seed));

    reg [31:0] snap1, snap2;
    reg [63:0] hashes [0:199];
    integer s, a, b, distinct_pairs, same_pairs, nn;
    reg [63:0] h1, h2;

    initial begin
        errors = 0; runs = 0; max_cycles = 0; done_pulses = 0; last_hash = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0; ss_rst = 1'b0;
        repeat (4) @(posedge clk);

        // 1) 200 seeds at the full size N = 10
        for (s = 0; s < 200; s = s + 1) begin
            run_gen(10, 32'h1000_0000 + s * 32'h9E37_79B1);
            hashes[s] = last_hash;
        end

        // 2) every size 2..10, 25 seeds each (previous bigger maze is left in memory)
        for (nn = 10; nn >= 2; nn = nn - 1)
            for (s = 0; s < 25; s = s + 1)
                run_gen(nn, 32'hA5A5_0000 + nn * 1000 + s);

        // 3) determinism: same seed and size twice, with another maze generated in between
        run_gen(10, 32'hDEAD_BEEF); h1 = last_hash;
        run_gen(6,  32'h0000_0777);
        run_gen(10, 32'hDEAD_BEEF); h2 = last_hash;
        if (h1 !== h2) begin errors = errors + 1; $display("FAIL: same seed gave different mazes"); end

        // 4) different seeds give different mazes (200 seeds at N=10)
        same_pairs = 0;
        for (a = 0; a < 200; a = a + 1)
            for (b = a + 1; b < 200; b = b + 1)
                if (hashes[a] === hashes[b]) same_pairs = same_pairs + 1;
        if (same_pairs != 0) begin errors = errors + 1; $display("FAIL: %0d duplicate mazes among 200 seeds", same_pairs); end

        // 5) seed 0 and out-of-range sizes are handled (0/1 -> 2, 12 -> 10)
        run_gen(10, 32'd0);
        run_gen2(10, 12, 32'h1234_5678);
        run_gen2(2, 0, 32'h0000_0042);
        run_gen2(2, 1, 32'h0000_0043);

        // 6) seed_source: fixed seed, changing counter, fresh capture per run
        ss_dbg = 1'b1; #1;
        if (ss_seed !== 32'hC0FFEE01) begin errors = errors + 1; $display("FAIL: fixed seed wrong"); end
        ss_dbg = 1'b0;
        repeat (5) @(posedge clk); snap1 = ss_seed;
        repeat (5) @(posedge clk); snap2 = ss_seed;
        if (snap1 === snap2) begin errors = errors + 1; $display("FAIL: seed does not move before latch"); end
        @(negedge clk); ss_latch = 1'b1; @(negedge clk); ss_latch = 1'b0;
        snap1 = ss_seed;
        repeat (20) @(posedge clk);
        if (ss_seed !== snap1) begin errors = errors + 1; $display("FAIL: seed not held after latch"); end
        @(negedge clk); ss_latch = 1'b1; @(negedge clk); ss_latch = 1'b0;
        snap2 = ss_seed;
        if (snap2 === snap1) begin errors = errors + 1; $display("FAIL: later generation did not capture a fresh seed"); end
        repeat (3) @(posedge clk);
        if (ss_seed !== snap2) begin errors = errors + 1; $display("FAIL: fresh seed was not held for its generation"); end

        $display("runs checked: %0d, longest generation: %0d cycles (%0d us at 100 MHz), done pulses: %0d",
                 runs, max_cycles, max_cycles / 100, done_pulses);
        if (errors == 0) $display("PASS: maze_gen - all mazes perfect and solvable, deterministic per seed, seed_source ok");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
