`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_story71_map;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg ce_pix = 1'b0;
    reg frame_tick = 1'b0;
    reg [3:0] n_cells = 4'd15;
    reg [9:0] pixel_x = 10'd320;
    reg [9:0] pixel_y = 10'd240;
    reg active_video = 1'b1;
    wire [9:0] maze_raddr;
    wire [3:0] r, g, b;
    wire hs, vs;
    wire signed [15:0] sin_snap, cos_snap;
    integer errors = 0;

    always #5 clk = ~clk;

    render dut (
        .clk(clk), .rst(rst), .ce_pix(ce_pix), .frame_tick(frame_tick),
        .game_state(2'b10), .n_cells(n_cells), .angle(12'd0),
        .sin_q(16'sd0), .cos_q(16'sd16384),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .hsync_in(1'b1), .vsync_in(1'b1), .maze_raddr(maze_raddr),
        .maze_rdata(1'b0), .start_col(5'd29), .start_row(5'd29),
        .goal_col(5'd1), .goal_row(5'd1), .ball_on(1'b0),
        .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(hs), .vga_vs(vs),
        .sin_snap(sin_snap), .cos_snap(cos_snap)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        #1;

        // Last tile of N=15 must be inside the active map and address 960.
        force dut.walk_x_q = (30 * 16 + 8) <<< 14;
        force dut.walk_y_q = (30 * 16 + 8) <<< 14;
        #1;
        if (!dut.in_map_now || maze_raddr !== 10'd960) begin
            $display("FAIL: N=15 last tile not addressed (in_map=%b addr=%0d)", dut.in_map_now, maze_raddr);
            errors = errors + 1;
        end
        release dut.walk_x_q;
        release dut.walk_y_q;

        // The same renderer must honor the smaller active extent and stride.
        n_cells = 4'd5;
        force dut.walk_x_q = (10 * 16 + 8) <<< 14;
        force dut.walk_y_q = (10 * 16 + 8) <<< 14;
        #1;
        if (!dut.in_map_now || maze_raddr !== 10'd120) begin
            $display("FAIL: N=5 last tile address wrong (in_map=%b addr=%0d)", dut.in_map_now, maze_raddr);
            errors = errors + 1;
        end
        force dut.walk_x_q = (11 * 16) <<< 14;
        #1;
        if (dut.in_map_now) begin
            $display("FAIL: renderer accepted a tile beyond N=5's 11x11 active map");
            errors = errors + 1;
        end
        release dut.walk_x_q;
        release dut.walk_y_q;

        if (errors == 0) $display("PASS: Story 7.1 renderer stage bounds and packed tile addresses through N=15");
        else             $display("FAIL: Story 7.1 renderer had %0d errors", errors);
        $finish;
    end
endmodule
