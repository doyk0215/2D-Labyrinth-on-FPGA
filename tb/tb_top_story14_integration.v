`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_top_story14_integration;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    reg btnD = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk;
    tri1 ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;

    integer errors = 0;
    integer start_count = 0;
    reg [31:0] seed_first, seed_second;
    reg [31:0] hash_first, hash_second;

    always #5 clk = ~clk;

    My_Top_Module #(.START_IN_MENU(1'b0), .POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3)) dut (
        .clk        (clk),
        .btnC       (btnC),
        .btnU       (1'b0),
        .btnL       (1'b0),
        .btnR       (1'b0),
        .btnD       (btnD),
        .sw         (16'h0006), // N=3, free-running seed
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

    always @(posedge clk) begin
        if (!btnC && dut.gen_start)
            start_count = start_count + 1;
        if (!btnC && (dut.game_state == `ST_GENERATE) && dut.maze_ram_i.ren_r !== 1'b0) begin
            $display("FAIL: render RAM read enabled during GENERATE");
            errors = errors + 1;
        end
    end

    task wait_state;
        input [`GAME_STATE_W-1:0] expected;
        integer guard;
        begin
            guard = 0;
            while ((dut.game_state !== expected) && (guard < 10000)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (dut.game_state !== expected) begin
                $display("FAIL: timed out waiting for top game_state %b; got %b", expected, dut.game_state);
                errors = errors + 1;
            end
        end
    endtask

    task compute_map_hash;
        output [31:0] hash;
        integer idx;
        begin
            hash = 32'h1357_9BDF;
            for (idx = 0; idx < 441; idx = idx + 1)
                hash = {hash[30:0], hash[31]} ^ {31'd0, dut.maze_ram_i.tile_mem[idx]};
        end
    endtask

    initial begin
        // Accelerate only the controller's frame-boundary input in simulation;
        // VGA timing and pixel generation continue to run normally.
        force dut.frame_tick = 1'b1;
        repeat (5) @(posedge clk);

        wait_state(`ST_PLAY);
        if (dut.gen_done_seen !== 1'b1 || dut.gen_busy !== 1'b0) begin
            $display("FAIL: startup did not complete a maze before PLAY");
            errors = errors + 1;
        end
        if (dut.start_col !== 5'd12 || dut.start_row !== 5'd12 ||
            dut.goal_col !== 5'd8 || dut.goal_row !== 5'd8) begin
            $display("FAIL: N=3 start/goal incorrect: start=(%0d,%0d) goal=(%0d,%0d)",
                     dut.start_col, dut.start_row, dut.goal_col, dut.goal_row);
            errors = errors + 1;
        end
        seed_first = dut.seed;
        compute_map_hash(hash_first);

        // A short BTND pulse requests exactly one new generation.
        @(negedge clk); btnD = 1'b1;
        repeat (4) @(negedge clk);
        btnD = 1'b0;
        wait_state(`ST_GENERATE);
        repeat (3) @(negedge clk);
        if (dut.maze_ram_i.ren_r !== 1'b0 || dut.render_enable_d !== 1'b0) begin
            $display("FAIL: render remained enabled during regeneration");
            errors = errors + 1;
        end
        while (dut.active_video_d !== 1'b1) @(negedge clk);
        #1;
        if ({vga_r, vga_g, vga_b} !== 12'h002) begin
            $display("FAIL: expected background during GENERATE, got %h", {vga_r, vga_g, vga_b});
            errors = errors + 1;
        end

        // A second press during GENERATE must not queue another generation.
        @(negedge clk); btnD = 1'b1;
        repeat (4) @(negedge clk);
        btnD = 1'b0;
        wait_state(`ST_PLAY);
        seed_second = dut.seed;
        compute_map_hash(hash_second);
        if (seed_second === seed_first) begin
            $display("FAIL: seed was reused for the next generation");
            errors = errors + 1;
        end
        if (hash_second === hash_first) begin
            $display("FAIL: second generated map is identical to the first");
            errors = errors + 1;
        end
        if (start_count != 2) begin
            $display("FAIL: got %0d gen_start pulses, expected 2", start_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: Story 1.4 top startup, fresh-seed regeneration, and render-read isolation");
        else
            $display("FAIL: Story 1.4 top integration had %0d errors", errors);
        release dut.frame_tick;
        $finish;
    end
endmodule
