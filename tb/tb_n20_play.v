`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// N = 20 play at the far tiles (columns and rows 32..40), where a 5-bit tile
// slice would alias onto 0..8.
// Physics: a 41 x 41 room. The ball clamps on the outer walls at +307 px
// (tile 40's edge, 640 - 328 - 5) and on interior walls at column 36 and row
// 36 at +269 px (592 - 328 + 5). Their aliases, column and row 4, are floor,
// so an aliased read would let the ball through. Goal bounds at (1,1) and at
// a far goal (39,39).
// Items: with N = 20 the box at (35,37) is picked up, and the box at its
// alias (3,5) is not; a debuff box at (33,39) is the debuff pool (index 4,
// with three buffs from N = 15 up).
module tb_n20_play;
    reg clk = 1'b0, rst = 1'b1, frame_tick = 1'b0, phys_init = 1'b0;
    reg [`N_CELLS_W-1:0] n_cells = 5'd20;
    reg [`COORD_W-1:0] spawn_col = 6'd39, spawn_row = 6'd20;
    reg [`COORD_W-1:0] goal_col = 6'd1, goal_row = 6'd1;
    reg signed [15:0] sin_q = 16'sd16384, cos_q = 16'sd0;
    wire [`MAP_ADDR_W-1:0] maze_raddr;
    wire maze_rdata;
    wire signed [`POS_W-1:0] ball_x, ball_y;
    wire signed [`VEL_W-1:0] vel_x, vel_y;
    wire phys_done, in_goal;
    always #5 clk = ~clk;

    reg map_we = 1'b0;
    reg [`MAP_ADDR_W-1:0] map_waddr = 0;
    reg map_wdata = 1'b1;
    reg map_t [0:`MAP_TILES-1];

    maze_ram ram_i (
        .clk(clk), .we(map_we), .waddr(map_waddr), .wdata(map_wdata),
        .raddr_p(maze_raddr), .rdata_p(maze_rdata),
        .ren_r(1'b0), .raddr_r({`MAP_ADDR_W{1'b0}}), .rdata_r()
    );
    ball_physics dut (
        .instant_respawn(1'b0),
        .effect_code(`ITEM_NONE),
        .clk(clk), .rst(rst), .frame_tick(frame_tick), .phys_init(phys_init),
        .phys_en(1'b1), .spawn_col(spawn_col), .spawn_row(spawn_row),
        .goal_col(goal_col), .goal_row(goal_row), .n_cells(n_cells),
        .sin_q(sin_q), .cos_q(cos_q), .restitution_sel(2'd0),
        .maze_raddr(maze_raddr), .maze_rdata(maze_rdata),
        .ball_x(ball_x), .ball_y(ball_y), .vel_x(vel_x), .vel_y(vel_y),
        .phys_done(phys_done), .in_goal(in_goal)
    );

    integer errors = 0;
    task fail; input [511:0] msg;
        begin
            errors = errors + 1;
            if (errors <= 10) $display("FAIL N=20 play: %0s (x=%0d y=%0d vx=%0d vy=%0d)", msg, ball_x, ball_y, vel_x, vel_y);
        end
    endtask

    integer i, row, col, guard;
    // inner = 0: outer walls only; 1: also column 36 (rows 1..39) and row 36.
    task load_room; input integer inner;
        begin
            for (row = 0; row < `MAP_STRIDE; row = row + 1)
                for (col = 0; col < `MAP_STRIDE; col = col + 1)
                    map_t[row * `MAP_STRIDE + col] = (row == 0 || col == 0 || row >= 40 || col >= 40) ||
                                                     (inner && (col == 36 || row == 36));
            for (i = 0; i < `MAP_TILES; i = i + 1) begin
                @(negedge clk); map_we = 1'b1; map_waddr = i; map_wdata = map_t[i];
            end
            @(negedge clk); map_we = 1'b0;
        end
    endtask
    task init_ball;
        begin
            @(negedge clk); phys_init = 1'b1;
            @(negedge clk); phys_init = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask
    task frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            guard = 0;
            while (!phys_done && guard < 100) begin @(negedge clk); guard = guard + 1; end
            if (!phys_done) fail("physics frame timed out");
        end
    endtask
    // Fall for up to 160 frames and check the ball settles at the clamp.
    task fall_to; input integer axis; input integer dir; input integer limit_q; input [255:0] what;
        integer f;
        begin
            for (f = 0; f < 160; f = f + 1) begin
                frame();
                if ((axis == 0) ? (dir > 0 ? ball_x > limit_q : ball_x < limit_q)
                                : (dir > 0 ? ball_y > limit_q : ball_y < limit_q))
                    fail("ball passed a wall");
            end
            if (((axis == 0) ? ball_x : ball_y) !== limit_q) fail(what);
        end
    endtask

    // ---- items ----
    reg item_done = 1'b0;
    reg signed [`POS_W-1:0] item_x = 0, item_y = 0;
    reg [8*`COORD_W-1:0] box_cols = {6'd0, 6'd0, 6'd0, 6'd33, 6'd0, 6'd0, 6'd3, 6'd35};
    reg [8*`COORD_W-1:0] box_rows = {6'd0, 6'd0, 6'd0, 6'd39, 6'd0, 6'd0, 6'd5, 6'd37};
    wire [7:0] box_visible;
    wire item_pulse, item_blocked;
    wire [2:0] item_index;
    wire [`ITEM_EFFECT_W-1:0] item_picked;
    item_ctrl #(.CLK_HZ(4), .EFFECT_SECONDS(2), .RESPAWN_SECONDS(3)) items_i (
        .clk(clk), .rst(rst), .game_state(`ST_PLAY), .phys_init(phys_init), .phys_done(item_done),
        .n_cells(n_cells), .ball_x(item_x), .ball_y(item_y),
        .box_cols(box_cols), .box_rows(box_rows), .box_valid(8'h13), .seed(32'h1234_5678),
        .roulette_busy(1'b0), .roulette_commit(1'b0),
        .box_visible(box_visible), .active_effect(), .effect_seconds(),
        .pickup_pulse(item_pulse), .pickup_index(item_index), .pickup_effect(item_picked),
        .debuff_blocked(item_blocked), .time_bonus_pulse(), .pending_valid(), .pending_effect()
    );
    // Ball on tile (c, r) of the N = 20 map: centre-relative Q9.8.
    task item_at; input integer c, r;
        begin item_x = (c - 20) * 4096; item_y = (r - 20) * 4096; end
    endtask
    task item_sample;
        begin @(negedge clk) item_done = 1'b1; @(negedge clk) item_done = 1'b0; end
    endtask

    initial begin
        repeat (4) @(negedge clk); rst = 1'b0;

        // Outer walls: right (+x) and bottom (+y), from a spawn near each.
        load_room(0);
        spawn_col = 6'd39; spawn_row = 6'd20; sin_q = 16'sd16384; cos_q = 16'sd0;
        init_ball(); fall_to(0, 1, 307 * 256, "right outer wall clamp at +307 px");
        spawn_col = 6'd20; spawn_row = 6'd39; sin_q = 16'sd0; cos_q = 16'sd16384;
        init_ball(); fall_to(1, 1, 307 * 256, "bottom outer wall clamp at +307 px");

        // Interior walls at column 36 and row 36, hit from the far side.
        load_room(1);
        spawn_col = 6'd39; spawn_row = 6'd20; sin_q = -16'sd16384; cos_q = 16'sd0;
        init_ball(); fall_to(0, -1, 269 * 256, "wall at column 36 clamp at +269 px");
        spawn_col = 6'd20; spawn_row = 6'd39; sin_q = 16'sd0; cos_q = -16'sd16384;
        init_ball(); fall_to(1, -1, 269 * 256, "wall at row 36 clamp at +269 px");

        // Goal bounds: (1,1) and a far goal (39,39).
        force dut.ball_x = -19 * 4096; force dut.ball_y = -19 * 4096; #1;
        if (!in_goal) fail("goal (1,1) not detected");
        goal_col = 6'd39; goal_row = 6'd39; #1;
        if (in_goal) fail("far goal detected at (1,1)");
        force dut.ball_x = 19 * 4096; force dut.ball_y = 19 * 4096; #1;
        if (!in_goal) fail("far goal (39,39) not detected");
        release dut.ball_x; release dut.ball_y;

        // Items: phys_init above loaded box_visible from box_valid.
        item_at(35, 37); item_sample();
        if (!item_pulse || item_index !== 3'd0) fail("box at (35,37) not picked up");
        if (box_visible[0] || !box_visible[1]) fail("wrong box hidden: (3,5) alias consumed");
        if (item_picked > `ITEM_TIME_BONUS) fail("box 0 is not from the buff pool");
        item_at(3, 5); item_sample();
        if (!item_pulse || item_index !== 3'd1) fail("box at (3,5) not picked up on its own tile");
        item_at(33, 39); item_sample();
        if (!item_pulse || item_index !== 3'd4) fail("debuff box at (33,39) not picked up");
        if (!item_blocked && (item_picked < `ITEM_REVERSE_GRAV ||
                             (item_picked > `ITEM_FOG && item_picked != `ITEM_INSTANT_DEATH)))
            fail("box 4 is not from the debuff pool");   // EPIC has four buff slots before its debuffs

        if (errors == 0)
            $display("PASS: N=20 play: wall clamps at tiles 36 and 40 on both axes, goal bounds (1,1) and (39,39), item pickup at (35,37) and (33,39) without aliasing");
        else
            $display("FAIL N=20 play: %0d errors", errors);
        $finish;
    end
endmodule
