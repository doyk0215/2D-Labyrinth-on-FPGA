`timescale 1ns / 1ps

module tb_render;

    reg clk = 1'b0;
    reg rst = 1'b1;
    wire [15:0] led;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire vga_hs;
    wire vga_vs;
    wire ps2_clk;
    wire ps2_data;
    wire oled_cs;
    wire oled_mosi;
    wire oled_sclk;
    wire oled_dc;
    wire oled_res;
    wire oled_vbatc;
    wire oled_vddc;

    always #5 clk = ~clk;

    top dut (
        .clk        (clk),
        .btnC       (rst),
        .btnU       (1'b0),
        .btnL       (1'b0),
        .btnR       (1'b0),
        .btnD       (1'b0),
        .sw         (16'h0001),
        .led        (led),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .vga_hs     (vga_hs),
        .vga_vs     (vga_vs),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
        .oled_cs    (oled_cs),
        .oled_mosi  (oled_mosi),
        .oled_sclk  (oled_sclk),
        .oled_dc    (oled_dc),
        .oled_res   (oled_res),
        .oled_vbatc (oled_vbatc),
        .oled_vddc  (oled_vddc)
    );

    task check_pixel;
        input [9:0] target_x;
        input [9:0] target_y;
        input [11:0] expected_rgb;
        begin
            while ((dut.timing_i.pixel_x !== target_x) ||
                   (dut.timing_i.pixel_y !== target_y))
                @(negedge clk);
            // Allow the synchronous maze RAM read and renderer pipeline to settle.
            @(posedge clk);
            #1;
            if ({vga_r, vga_g, vga_b} !== expected_rgb) begin
                $display("FAIL: pixel (%0d,%0d) RGB=%h expected=%h",
                         target_x, target_y, {vga_r, vga_g, vga_b}, expected_rgb);
                $finish;
            end
        end
    endtask

    integer r, c, floors;
    reg [11:0] exp_rgb;

    // The fixed debug seed (sw[0]) makes the generated maze repeatable. The
    // maze is read back from maze_ram and every tile of the displayed map is
    // checked against it, so the test does not depend on which maze is made.
    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Generation starts when reset is released and takes about 11 us.
        wait (dut.gen_done_seen === 1'b1);
        // Story 1.4 holds the renderer off until the frame-boundary handoff.
        wait (dut.game_state === 2'b10); // PLAY
        repeat (2) @(posedge clk);

        if (dut.start_col !== 5'd1 || dut.start_row !== 5'd1 ||
            dut.goal_col !== 5'd19 || dut.goal_row !== 5'd19) begin
            $display("FAIL: start (%0d,%0d) goal (%0d,%0d), expected (1,1) and (19,19)",
                     dut.start_col, dut.start_row, dut.goal_col, dut.goal_row);
            $finish;
        end

        floors = 0;
        for (r = 0; r < 441; r = r + 1)
            if (dut.maze_ram_i.tile_mem[r] === 1'b0) floors = floors + 1;
        if (floors != 199) begin // perfect 10x10 maze: 2*N*N-1 floor tiles
            $display("FAIL: %0d floor tiles, expected 199", floors);
            $finish;
        end

        // Screen map bounds are x=152..487 and y=72..407. Targets are in
        // raster order so the whole map is checked within one frame.
        check_pixel(10'd320, 10'd71, 12'h002); // background above maze
        for (r = 0; r < 21; r = r + 1) begin
            check_pixel(10'd151, 10'd80 + 16 * r, 12'h002); // background left
            for (c = 0; c < 21; c = c + 1) begin
                if (c == dut.start_col && r == dut.start_row)
                    exp_rgb = 12'h0f0;                       // start tile
                else if (c == dut.goal_col && r == dut.goal_row)
                    exp_rgb = 12'hf00;                       // goal tile
                else if (dut.maze_ram_i.tile_mem[r * 21 + c])
                    exp_rgb = 12'hfff;                       // wall
                else
                    exp_rgb = 12'h346;                       // floor
                check_pixel(10'd160 + 16 * c, 10'd80 + 16 * r, exp_rgb);
            end
            check_pixel(10'd488, 10'd80 + 16 * r, 12'h002); // background right
        end
        check_pixel(10'd320, 10'd408, 12'h002); // background below maze

        $display("PASS: generated maze (fixed seed) wall, floor, start, goal, centering, and background pixels");
        $finish;
    end

endmodule
