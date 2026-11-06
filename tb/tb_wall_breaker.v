`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// wall_breaker: 5 x 5 interior blast on the next physics completion in PLAY.
// The bench keeps its own 64 x 64 tile array (1 = wall) and applies the
// breaker's write port to it, then compares every tile against an independent
// integer model of the blast.
module tb_wall_breaker;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, phys_init = 1'b0, phys_done = 1'b0, trigger = 1'b0;
    reg [`GAME_STATE_W-1:0] state = `ST_PLAY;
    reg [`N_CELLS_W-1:0] n = 5'd10;
    reg signed [`POS_W-1:0] bx = 0, by = 0;
    wire we, wdata, busy;
    wire [`MAP_ADDR_W-1:0] waddr;

    wall_breaker dut (.clk(clk), .rst(rst), .phys_init(phys_init), .game_state(state),
        .phys_done(phys_done), .trigger(trigger), .n_cells(n), .ball_x(bx), .ball_y(by),
        .we(we), .waddr(waddr), .wdata(wdata), .busy(busy));

    reg tile [0:`MAP_TILES-1];
    integer writes = 0;
    always @(posedge clk) if (we) begin tile[waddr] <= wdata; writes <= writes + 1; end

    task fail;
        input [511:0] msg;
        begin $display("FAIL wall_breaker: %0s", msg); $finish; end
    endtask
    task cycles; input integer c; begin repeat (c) @(negedge clk); end endtask
    task fill_walls; integer i; begin for (i = 0; i < `MAP_TILES; i = i + 1) tile[i] = 1'b1; writes = 0; end endtask
    task place; input integer c, r; begin bx = (c - n) * 4096; by = (r - n) * 4096; end endtask
    task pulse_trigger; begin @(negedge clk); trigger = 1; @(negedge clk); trigger = 0; end endtask
    task pulse_done; begin @(negedge clk); phys_done = 1; @(negedge clk); phys_done = 0; end endtask

    // Independent model: tile (c,r) must be floor iff it is interior (1..2N-1)
    // and within 2 tiles of the ball tile (bc, br).
    task check_block; input integer bc, br; input integer expect_clear;
        integer c, r, want_floor;
        begin
            for (r = 0; r < 64; r = r + 1)
                for (c = 0; c < 64; c = c + 1) begin
                    want_floor = expect_clear && c >= 1 && r >= 1 && c <= 2 * n - 1 && r <= 2 * n - 1 &&
                                 c >= bc - 2 && c <= bc + 2 && r >= br - 2 && r <= br + 2;
                    if (tile[r * 64 + c] !== (want_floor ? 1'b0 : 1'b1)) begin
                        $display("tile (%0d,%0d) = %b, expected %b (ball tile %0d,%0d, N=%0d)",
                                 c, r, tile[r * 64 + c], want_floor ? 1'b0 : 1'b1, bc, br, n);
                        fail("blast mismatch");
                    end
                end
        end
    endtask
    task break_at; input integer c, r;
        begin place(c, r); pulse_trigger(); pulse_done(); cycles(40); end
    endtask

    initial begin
        fill_walls();
        repeat (3) @(negedge clk); rst = 0; cycles(2);

        // Centre cell, N = 10.
        place(9, 9); pulse_trigger(); cycles(60);
        if (writes != 0 || busy) fail("wrote before a physics completion");
        pulse_done(); cycles(40);
        check_block(9, 9, 1);
        if (writes != 25) fail("a 5x5 interior blast writes 25 tiles");
        if (busy) fail("still busy after the sweep");

        // A second physics completion does nothing: the request was consumed.
        fill_walls(); pulse_done(); cycles(40); check_block(9, 9, 0);

        // Near the top-left border: row/column 0 stay wall.
        fill_walls(); break_at(1, 1); check_block(1, 1, 1);
        if (writes != 9) fail("corner blast writes only the 3x3 interior tiles");
        // Bottom-right interior corner for N = 10 (tile 19).
        fill_walls(); break_at(19, 19); check_block(19, 19, 1);
        fill_walls(); break_at(19, 1); check_block(19, 1, 1);

        // N = 20: far corner uses 6-bit tile coordinates with no alias.
        n = 5'd20; fill_walls(); break_at(39, 39); check_block(39, 39, 1);
        fill_walls(); break_at(36, 20); check_block(36, 20, 1);
        n = 5'd10;

        // Trigger and phys_done in the same clock.
        fill_walls(); place(5, 11);
        @(negedge clk); trigger = 1; phys_done = 1; @(negedge clk); trigger = 0; phys_done = 0; cycles(40);
        check_block(5, 11, 1);

        // A request made before a pause waits for PLAY and the next completion.
        fill_walls(); place(11, 5); pulse_trigger();
        state = `ST_PAUSED; cycles(30); pulse_done(); cycles(40);
        if (writes != 0) fail("breaker wrote while paused");
        state = `ST_PLAY; cycles(4); pulse_done(); cycles(40); check_block(11, 5, 1);

        // Leaving PLAY for good drops the request.
        fill_walls(); place(7, 7); pulse_trigger();
        state = `ST_WIN; cycles(4); state = `ST_PLAY; cycles(4); pulse_done(); cycles(40);
        check_block(7, 7, 0);
        // So does a new maze (phys_init).
        fill_walls(); pulse_trigger(); @(negedge clk); phys_init = 1; @(negedge clk); phys_init = 0;
        pulse_done(); cycles(40); check_block(7, 7, 0);
        // A completion outside PLAY is ignored.
        fill_walls(); pulse_trigger(); state = `ST_PAUSED; pulse_done(); state = `ST_PLAY; cycles(40);
        if (writes != 0) fail("completion while paused started a blast");

        $display("PASS: wall breaker 5x5 interior blast, border and N=20 corner clamp, waits for physics completion, pause kept, restart drops it");
        $finish;
    end
    initial begin #20000000; fail("timeout"); end
endmodule
