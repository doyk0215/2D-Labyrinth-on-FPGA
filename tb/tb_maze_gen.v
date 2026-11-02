`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for maze_gen and seed_source (Stories 1.3 and 7.5).
// For many seeds and sizes it checks: done pulse, start/goal tiles, outer
// walls, nothing outside the maze region, BFS connectivity/reachability,
// maximum opening counts (perfect EASY, up to K extra openings on loop stages),
// deterministic output per seed, and diversity across seeds.
module tb_maze_gen;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         gen_start = 1'b0;
    reg  [3:0]  n_cells = 4'd10;
    reg  [31:0] seed = 32'd1;
    wire        gen_busy, gen_done, we, wdata;
    wire [`MAP_ADDR_W-1:0] waddr;
    wire [4:0]  start_col, start_row, goal_col, goal_row;
    wire [19:0] box_cols, box_rows;
    wire [3:0]  box_valid;

    always #5 clk = ~clk;

    maze_gen dut (
        .clk(clk), .rst(rst), .gen_start(gen_start), .n_cells(n_cells), .seed(seed),
        .gen_busy(gen_busy), .gen_done(gen_done), .we(we), .waddr(waddr), .wdata(wdata),
        .start_col(start_col), .start_row(start_row), .goal_col(goal_col), .goal_row(goal_row),
        .box_cols(box_cols), .box_rows(box_rows), .box_valid(box_valid)
    );

    // ---- behavioural maze RAM (32 x 32 tiles at {row, col}, 1 = wall) ----
    reg mem [0:`MAP_TILES-1];
    integer i;
    initial for (i = 0; i < `MAP_TILES; i = i + 1) mem[i] = 1'b0;   // stale floor on purpose
    always @(posedge clk) if (we) mem[waddr] <= wdata;

    // ---- the last 8 floor writes of a run (the loop pass writes last) ----
    integer floor_writes;
    integer wlog [0:7];
    always @(posedge clk) if (we && !wdata) begin
        wlog[floor_writes % 8] = waddr;
        floor_writes = floor_writes + 1;
    end

    // ---- bookkeeping ----
    integer errors;
    integer runs;
    integer cycles, max_cycles;
    integer done_pulses;
    integer n10_below_cap, n10_at_cap, n15_below_cap, n15_at_cap;
    integer max_stack_depth = 0;
    always @(posedge clk) if (gen_done) done_pulses <= done_pulses + 1;
    always @(negedge clk) if (gen_busy) begin
        if (dut.sp > 225) begin
            errors = errors + 1;
            $display("FAIL: DFS stack pointer exceeded 225 (%0d)", dut.sp);
        end
        if (dut.sp > max_stack_depth) max_stack_depth = dut.sp;
    end

    // ---- BFS over floor tiles ----
    reg      seen [0:`MAP_TILES-1];
    integer  queue [0:`MAP_TILES-1];
    integer  qh, qt, floor_total, reached, cur, c, r, nb, dim;
    reg      goal_reached;

    task bfs_check;
        input integer N;
        input integer sc, sr, gc, gr;
        integer k;
        begin
            floor_total = 0; dim = 2 * N + 1;
            for (k = 0; k < `MAP_TILES; k = k + 1) begin
                seen[k] = 1'b0;
                if (!mem[k]) floor_total = floor_total + 1;
            end
            qh = 0; qt = 0; reached = 0; goal_reached = 1'b0;
            queue[qt] = sr * `MAP_STRIDE + sc; qt = qt + 1; seen[sr * `MAP_STRIDE + sc] = 1'b1;
            while (qh < qt) begin
                cur = queue[qh]; qh = qh + 1;
                reached = reached + 1;
                c = cur % `MAP_STRIDE; r = cur / `MAP_STRIDE;
                if (c == gc && r == gr) goal_reached = 1'b1;
                if (r > 0)  begin nb = cur - `MAP_STRIDE; if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (r < dim-1) begin nb = cur + `MAP_STRIDE; if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (c > 0)  begin nb = cur - 1;  if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
                if (c < dim-1) begin nb = cur + 1;  if (!mem[nb] && !seen[nb]) begin seen[nb] = 1'b1; queue[qt] = nb; qt = qt + 1; end end
            end
        end
    endtask

    function integer max_loop_count;
        input integer N;
        begin
            case (N)
                10: max_loop_count = 3;  // HARD
                15: max_loop_count = 5;  // largest stage
                default: max_loop_count = 0;
            endcase
        end
    endfunction

    // ---- hash of the memory image ----
    function [63:0] mem_hash;
        input dummy;
        integer k;
        reg [63:0] h;
        begin
            h = 64'hCBF29CE484222325;
            for (k = 0; k < `MAP_TILES; k = k + 1)
                h = (h ^ {63'd0, mem[k]}) * 64'h100000001B3;
            h = (h ^ {20'd0, box_valid, box_rows, box_cols}) * 64'h100000001B3;   // boxes too
            mem_hash = h;
        end
    endfunction

    // ---- one generation run, then all checks ----
    reg [63:0] last_hash;
    reg [15:0] buff_pairs_seen = 16'd0;   // which quadrant pairs held the buffs
    task run_gen;
        input integer N;
        input [31:0] s;
        begin run_gen2(N, N, s); end
    endtask

    // N = expected size; drive = value put on n_cells.
    task run_gen2;
        input integer N;
        input integer drive;
        input [31:0] s;
        integer limit, k, outside_floor, perimeter_floor, map_col, map_row;
        integer edge_openings, edge_row, edge_col;
        integer K, cap, band, band_first, band_last, loop_addr, loop_row, loop_col;
        integer band_found, band_seen;
        integer bx, bcol, brow, bcx, bcy, bq, quad_mask, buff_mask;
        begin
            n_cells = drive[3:0]; seed = s; floor_writes = 0;
            @(negedge clk); gen_start = 1'b1;
            @(negedge clk); gen_start = 1'b0;
            if (box_valid !== 4'b0000) begin
                errors = errors + 1; $display("FAIL N=%0d seed=%h: boxes still valid after gen_start", N, s);
            end
            cycles = 0; limit = 100000;
            while (!gen_done && cycles < limit) begin @(posedge clk); cycles = cycles + 1; end
            @(negedge clk);
            if (cycles >= limit) begin
                errors = errors + 1; $display("FAIL N=%0d seed=%h: timeout", N, s);
            end else begin
                if (cycles > max_cycles) max_cycles = cycles;
                if (gen_busy) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: busy after done", N, s); end

                // start/goal tiles: start bottom-right, goal top-left
                if (start_col !== (2 * N - 1) || start_row !== (2 * N - 1) ||
                    goal_col !== 1 || goal_row !== 1) begin
                    errors = errors + 1;
                    $display("FAIL N=%0d seed=%h: start (%0d,%0d) goal (%0d,%0d)", N, s,
                             start_col, start_row, goal_col, goal_row);
                end
                if (mem[start_row * `MAP_STRIDE + start_col] || mem[goal_row * `MAP_STRIDE + goal_col]) begin
                    errors = errors + 1; $display("FAIL N=%0d seed=%h: start or goal is a wall", N, s);
                end

                // Nothing outside the active stage map, and an intact outer wall.
                outside_floor = 0; perimeter_floor = 0;
                for (k = 0; k < `MAP_TILES; k = k + 1) begin
                    map_col = k % `MAP_STRIDE;
                    map_row = k / `MAP_STRIDE;
                    if ((map_col > 2 * N || map_row > 2 * N) && !mem[k])
                        outside_floor = outside_floor + 1;
                    if ((map_col == 0 || map_row == 0 || map_col == 2 * N || map_row == 2 * N) &&
                        map_col <= 2 * N && map_row <= 2 * N && !mem[k])
                        perimeter_floor = perimeter_floor + 1;
                end
                if (outside_floor != 0) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: %0d floor tiles outside the active map", N, s, outside_floor); end
                if (perimeter_floor != 0) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: gap in outer wall", N, s); end

                // Count open adjacencies between logical cells. Cell tiles
                // are odd/odd; passages lie at even/odd or odd/even tiles.
                edge_openings = 0;
                for (edge_row = 0; edge_row < N; edge_row = edge_row + 1)
                    for (edge_col = 0; edge_col < N; edge_col = edge_col + 1) begin
                        if ((edge_col < N-1) && !mem[(2*edge_row+1)*`MAP_STRIDE + (2*edge_col+2)])
                            edge_openings = edge_openings + 1;
                        if ((edge_row < N-1) && !mem[(2*edge_row+2)*`MAP_STRIDE + (2*edge_col+1)])
                            edge_openings = edge_openings + 1;
                    end
                cap = max_loop_count(N);
                K = edge_openings - (N * N - 1);
                if (K < 0 || K > cap) begin
                    errors = errors + 1;
                    $display("FAIL N=%0d seed=%h: %0d extra openings, allowed 0..%0d",
                             N, s, K, cap);
                end
                if (N == 10) begin
                    if (K < cap) n10_below_cap = n10_below_cap + 1;
                    if (K == cap) n10_at_cap = n10_at_cap + 1;
                end else if (N == 15) begin
                    if (K < cap) n15_below_cap = n15_below_cap + 1;
                    if (K == cap) n15_at_cap = n15_at_cap + 1;
                end

                // Loop placement: at most one of the last K floor writes may
                // occupy each existing row band. Skipped bands stay empty.
                band_seen = 0;
                for (band = 0; band < K; band = band + 1) begin
                    loop_addr = wlog[(floor_writes - K + band) % 8];
                    loop_row   = loop_addr / `MAP_STRIDE;
                    loop_col   = loop_addr % `MAP_STRIDE;
                    band_found = -1;
                    for (k = 0; k < cap; k = k + 1) begin
                        band_first = 6 * k + 1;
                        band_last  = (k == cap - 1) ? 2 * N - 1 : 6 * k + 5;
                        if (loop_row >= band_first && loop_row <= band_last)
                            band_found = k;
                    end
                    if (((loop_row + loop_col) % 2) != 1 || band_found < 0 ||
                        loop_col < 1 || loop_col > 2 * N - 1) begin
                        errors = errors + 1;
                        $display("FAIL N=%0d seed=%h: loop at tile (%0d,%0d) is outside the configured bands",
                                 N, s, loop_col, loop_row);
                    end else if (band_seen & (1 << band_found)) begin
                        errors = errors + 1;
                        $display("FAIL N=%0d seed=%h: more than one loop in band %0d", N, s, band_found);
                    end else begin
                        band_seen = band_seen | (1 << band_found);
                    end
                end

                // Item boxes: N >= 4 has one per quadrant (split at N/2) on a
                // floor cell that is not the start or goal; N < 4 has none.
                if (box_valid !== ((N >= 4) ? 4'b1111 : 4'b0000)) begin
                    errors = errors + 1; $display("FAIL N=%0d seed=%h: box_valid=%b", N, s, box_valid);
                end else if (N >= 4) begin
                    quad_mask = 0; buff_mask = 0;
                    for (bx = 0; bx < 4; bx = bx + 1) begin
                        bcol = box_cols[5*bx +: 5]; brow = box_rows[5*bx +: 5];
                        bcx = (bcol - 1) / 2; bcy = (brow - 1) / 2;
                        bq = (bcy < N / 2) ? ((bcx < N / 2) ? 0 : 1) : ((bcx < N / 2) ? 3 : 2);
                        quad_mask = quad_mask | (1 << bq);
                        if (bx < 2) buff_mask = buff_mask | (1 << bq);
                        if ((bcol % 2) != 1 || (brow % 2) != 1 || bcol > 2 * N - 1 || brow > 2 * N - 1 ||
                            mem[brow * `MAP_STRIDE + bcol] ||
                            (bcol == start_col && brow == start_row) || (bcol == goal_col && brow == goal_row)) begin
                            errors = errors + 1;
                            $display("FAIL N=%0d seed=%h: box %0d at tile (%0d,%0d) is not a free floor cell", N, s, bx, bcol, brow);
                        end
                    end
                    if (quad_mask != 15) begin
                        errors = errors + 1; $display("FAIL N=%0d seed=%h: boxes do not cover all four quadrants (%b)", N, s, quad_mask[3:0]);
                    end
                    buff_pairs_seen[buff_mask[3:0]] = 1'b1;
                end

                // BFS: every floor tile is connected and the goal is reachable.
                bfs_check(N, start_col, start_row, goal_col, goal_row);
                if (!goal_reached) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: goal not reachable", N, s); end
                if (reached != floor_total) begin errors = errors + 1; $display("FAIL N=%0d seed=%h: %0d of %0d floor tiles reachable", N, s, reached, floor_total); end
                if (floor_total != N * N + edge_openings) begin
                    errors = errors + 1;
                    $display("FAIL N=%0d seed=%h: %0d floor tiles, expected %0d", N, s, floor_total, N*N+edge_openings);
                end

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
        n10_below_cap = 0; n10_at_cap = 0; n15_below_cap = 0; n15_at_cap = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0; ss_rst = 1'b0;
        repeat (4) @(posedge clk);

        // 1) 200 HARD loop-stage seeds retain the large-stage diversity check.
        for (s = 0; s < 200; s = s + 1) begin
            run_gen(10, 32'h1000_0000 + s * 32'h9E37_79B1);
            hashes[s] = last_hash;
        end

        // HARD and N=15 loop counts must vary by seed while staying within
        // their caps; every selected loop remains in a distinct row band.
        for (s = 0; s < 200; s = s + 1)
            run_gen(15, 32'h1500_0000 + s * 32'h7F4A_7C15);

        // 2) every size 2..15, 25 seeds each, stressing N=15 stack capacity.
        for (nn = 15; nn >= 2; nn = nn - 1)
            for (s = 0; s < 25; s = s + 1)
                run_gen(nn, 32'hA5A5_0000 + nn * 1000 + s);

        // 3) determinism at EASY, HARD, and N=15, with another size between runs.
        run_gen(5, 32'hDEAD_0005); h1 = last_hash;
        run_gen(7, 32'h0000_0777);
        run_gen(5, 32'hDEAD_0005); h2 = last_hash;
        if (h1 !== h2) begin errors = errors + 1; $display("FAIL: EASY same seed gave different mazes"); end

        run_gen(10, 32'hDEAD_0010); h1 = last_hash;
        run_gen(6, 32'h0000_0777);
        run_gen(10, 32'hDEAD_0010); h2 = last_hash;
        if (h1 !== h2) begin errors = errors + 1; $display("FAIL: HARD same seed gave different mazes"); end

        run_gen(15, 32'hDEAD_BEEF); h1 = last_hash;
        run_gen(6,  32'h0000_0777);
        run_gen(15, 32'hDEAD_BEEF); h2 = last_hash;
        if (h1 !== h2) begin errors = errors + 1; $display("FAIL: N=15 same seed gave different mazes"); end

        // 4) different seeds give different mazes (200 seeds at N=10)
        same_pairs = 0;
        for (a = 0; a < 200; a = a + 1)
            for (b = a + 1; b < 200; b = b + 1)
                if (hashes[a] === hashes[b]) same_pairs = same_pairs + 1;
        if (same_pairs != 0) begin errors = errors + 1; $display("FAIL: %0d duplicate mazes among 200 seeds", same_pairs); end
        if (n10_below_cap == 0 || n10_at_cap == 0) begin
            errors = errors + 1;
            $display("FAIL: N=10 did not exercise both below-cap and at-cap loop counts");
        end
        if (n15_below_cap == 0 || n15_at_cap == 0) begin
            errors = errors + 1;
            $display("FAIL: N=15 did not exercise both below-cap and at-cap loop counts");
        end

        // 5) seed 0 and out-of-range sizes are handled (0/1 -> 2; 15 is max).
        run_gen(15, 32'd0);
        run_gen2(15, 15, 32'h1234_5678);
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

        // Every pair of quadrants (3, 5, 6, 9, 10, 12 as masks) held the buffs at least once.
        if (buff_pairs_seen !== 16'h1668) begin
            errors = errors + 1; $display("FAIL: buff quadrant pairs seen %h, expected all six (1668)", buff_pairs_seen);
        end

        $display("runs checked: %0d, longest generation: %0d cycles (%0d us at 100 MHz), max DFS stack depth: %0d/225, done pulses: %0d",
                 runs, max_cycles, max_cycles / 100, max_stack_depth, done_pulses);
        if (errors == 0) $display("PASS: maze_gen - EASY perfect, HARD/N=15 loop counts within caps, connected, solvable and deterministic; seed_source ok; item boxes one per quadrant");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
