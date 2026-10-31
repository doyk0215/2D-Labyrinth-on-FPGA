`timescale 1ns / 1ps

// Story 9.6: reads every pixel of every item icon from item_icon_rom and checks
// it against the data files written by scripts/make_item_icons.ps1. The run
// script copies tb/data/*.mem into the simulator's working folder.
module tb_item_icon_rom;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg [2:0] icon = 3'd0;
    reg [3:0] x = 4'd0, y = 4'd0;
    wire [1:0] idx;
    wire [15:0] rgb;
    item_icon_rom dut (.clk(clk), .icon(icon), .x(x), .y(y), .idx(idx), .rgb(rgb));

    reg [1:0]  ref_idx [0:2047];
    reg [15:0] ref_pal [0:31];
    integer errors = 0, checked = 0;
    integer n, a, i, j, px, py;
    integer used2, used3, same;
    reg [10:0] addr;

    task fail;
        input [511:0] message;
        begin
            $display("FAIL item icon ROM: %0s (icon=%0d x=%0d y=%0d idx=%0d rgb=%h)",
                     message, icon, x, y, idx, rgb);
            errors = errors + 1;
        end
    endtask

    // Drive one pixel address, let the ROM answer one clock later, and check it.
    task read_pixel;
        input [10:0] pixel_addr;
        begin
            @(negedge clk);
            icon = pixel_addr[10:8]; y = pixel_addr[7:4]; x = pixel_addr[3:0];
            @(posedge clk); #1;
            if (idx !== ref_idx[pixel_addr]) fail("index differs from the data file");
            if (rgb !== ref_pal[{icon, idx}]) fail("colour differs from the palette file");
            checked = checked + 1;
        end
    endtask

    initial begin
        $readmemh("item_icons.mem", ref_idx);
        $readmemh("item_icons_palette.mem", ref_pal);
        if (ref_idx[0] !== 2'd1 || ref_pal[1] !== 16'h0640) begin
            $display("FAIL item icon ROM: data files were not loaded (copy tb/data/*.mem next to the simulation)");
            $finish;
        end

        // Every pixel of every icon in address order.
        for (a = 0; a < 2048; a = a + 1) read_pixel(a);
        // Then in a scattered order, so a stale or neighbouring value cannot pass.
        for (n = 0; n < 2048; n = n + 1) read_pixel((n * 37 + 11) % 2048);

        for (i = 0; i < 8; i = i + 1) begin
            used2 = 0; used3 = 0;
            for (py = 0; py < 16; py = py + 1) begin
                for (px = 0; px < 16; px = px + 1) begin
                    addr = i * 256 + py * 16 + px;
                    // The outer ring is the frame: green for buffs (icons 0 to 2), red for debuffs.
                    if (px == 0 || px == 15 || py == 0 || py == 15) begin
                        if (ref_idx[addr] !== 2'd1) begin icon = i; x = px; y = py; fail("frame pixel is not index 1"); end
                    end
                    if (ref_idx[addr] == 2'd2) used2 = used2 + 1;
                    if (ref_idx[addr] == 2'd3) used3 = used3 + 1;
                end
            end
            if (ref_pal[i*4 + 0] !== 16'h0000) begin icon = i; fail("colour 0 is not black"); end
            if (ref_pal[i*4 + 1] !== ((i < 3) ? 16'h0640 : 16'hD800)) begin icon = i; fail("frame colour is not green for buffs and red for debuffs"); end
            if (used2 == 0 || used3 == 0) begin icon = i; fail("icon does not use both of its own colours"); end
            // No two icons are the same picture.
            for (j = i + 1; j < 8; j = j + 1) begin
                same = 1;
                for (a = 0; a < 256; a = a + 1) if (ref_idx[i*256 + a] !== ref_idx[j*256 + a]) same = 0;
                if (same) begin icon = j; fail("two icons have identical pixels"); end
            end
        end

        if (errors == 0)
            $display("PASS: item icon ROM - all 8 icons x 256 pixels and 32 palette colours match the data files; %0d reads, frame colours and distinct icons checked", checked);
        else
            $display("FAIL: item icon ROM had %0d errors", errors);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: item icon ROM bench timed out");
        $finish;
    end
endmodule
