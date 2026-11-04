`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// CUSTOM stage sizes. For every N = 2..20 and several seeds, maze_gen builds a
// connected, solvable map with wall outside the (2N+1) x (2N+1) area, the
// stage's box count (0 up to N = 5, 4 below 15, 6 from 15) on distinct floor
// cells that are not the start or goal, and at most N/3 loop openings from
// N = 8 (none below). game_timer loads 12 s x N for every N, and the preset
// parameters at N = 5/10/15/20 when they differ from it.
module tb_custom_stage;
    reg clk = 1'b0, rst = 1'b1, gen_start = 1'b0;
    reg [`N_CELLS_W-1:0] n_cells = 5'd2;
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

    // Two timers: default parameters (12 s x N everywhere), and distinct
    // presets so the N = 5/10/15/20 entries are seen to come from them.
    reg phys_init = 1'b0;
    wire [7:0] min_d, sec_d, min_p, sec_p;
    game_timer #(.CLK_HZ(4)) timer_d (
        .clk(clk), .rst(rst), .preserve_time(1'b0), .maze_pixel_visible(1'b0),
        .player_action(1'b0), .time_bonus_pulse(1'b0), .game_state(`ST_GENERATE),
        .phys_init(phys_init), .n_cells(n_cells),
        .elapsed_minutes_bcd(min_d), .elapsed_seconds_bcd(sec_d), .time_up()
    );
    game_timer #(.CLK_HZ(4), .EASY_SECONDS(61), .HARD_SECONDS(122), .HUGE_SECONDS(183),
                 .XL_SECONDS(244), .SECONDS_PER_CELL(7)) timer_p (
        .clk(clk), .rst(rst), .preserve_time(1'b0), .maze_pixel_visible(1'b0),
        .player_action(1'b0), .time_bonus_pulse(1'b0), .game_state(`ST_GENERATE),
        .phys_init(phys_init), .n_cells(n_cells),
        .elapsed_minutes_bcd(min_p), .elapsed_seconds_bcd(sec_p), .time_up()
    );

    reg mem [0:`MAP_TILES-1];
    integer i;
    initial for (i = 0; i < `MAP_TILES; i = i + 1) mem[i] = 1'b0;   // stale floor on purpose
    always @(posedge clk) if (we) mem[waddr] <= wdata;

    integer errors = 0;
    task fail; input [511:0] msg;
        begin
            errors = errors + 1;
            if (errors <= 10) $display("FAIL custom stage: %0s (seed %08h, N %0d)", msg, seed, n_cells);
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

    function [15:0] bcd_time;
        input integer seconds;
        reg [3:0] m10, m1, s10, s1;
        begin
            m10 = (seconds / 60) / 10; m1 = (seconds / 60) % 10;
            s10 = (seconds % 60) / 10; s1 = (seconds % 60) % 10;
            bcd_time = {m10, m1, s10, s1};
        end
    endfunction

    integer n, s, k, j, cx, cy, loops, loop_cap, boxes, loops_seen, preset;
    initial begin
        repeat (3) @(negedge clk); rst = 1'b0;
        for (n = 2; n <= 20; n = n + 1) begin
            loop_cap = (n < 8) ? 0 : n / 3;
            boxes = (n <= 5) ? 0 : (n < 15) ? 4 : 6;
            loops_seen = 0;
            for (s = 0; s < 12; s = s + 1) begin
                n_cells = n; seed = 32'h9e37_79b9 * (s + 31 * n) ^ 32'h0000_c0de;
                generate_maze();
                check_map(n);
                loops = floor_tiles - (2 * n * n - 1);
                if (loops > loop_cap) fail("more loop openings than the stage allows");
                if (loops > loops_seen) loops_seen = loops;
                if (box_valid !== (6'b111111 >> (6 - boxes))) fail("wrong number of item boxes");
                for (k = 0; k < boxes; k = k + 1) begin
                    cx = box_cols[k * `COORD_W +: `COORD_W];
                    cy = box_rows[k * `COORD_W +: `COORD_W];
                    if ((cx % 2) != 1 || (cy % 2) != 1 || cx > 2 * n - 1 || cy > 2 * n - 1)
                        fail("box not on a cell of the map");
                    if (cx == 2 * n - 1 && cy == 2 * n - 1) fail("box on the start cell");
                    if (cx == 1 && cy == 1) fail("box on the goal cell");
                    if (mem[cy * `MAP_STRIDE + cx]) fail("box on a wall");
                    for (j = 0; j < k; j = j + 1)
                        if (box_cols[j * `COORD_W +: `COORD_W] == cx && box_rows[j * `COORD_W +: `COORD_W] == cy)
                            fail("two boxes share a cell");
                end
            end
            if (loop_cap != 0 && loops_seen == 0) fail("no loop opening in 12 seeds");

            @(negedge clk) phys_init = 1'b1;
            @(negedge clk) phys_init = 1'b0;
            if ({min_d, sec_d} !== bcd_time(12 * n)) fail("default time limit is not 12 s x N");
            preset = (n == 5) ? 61 : (n == 10) ? 122 : (n == 15) ? 183 : (n == 20) ? 244 : 7 * n;
            if ({min_p, sec_p} !== bcd_time(preset)) fail("time limit ignores the preset or SECONDS_PER_CELL");
        end
        if (errors == 0)
            $display("PASS: custom stage N=2..20 maze_gen connected and solvable with the stage box and loop counts, walls outside the map, time limits 12 s x N and presets");
        else
            $display("FAIL custom stage: %0d errors", errors);
        $finish;
    end
endmodule
