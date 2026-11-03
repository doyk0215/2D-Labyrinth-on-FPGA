`timescale 1ns / 1ps

module tb_monitor_menu_overlay;
    localparam [143:0] EXPECTED_LINE = "U/D = SELECT STAGE";
    localparam [95:0] REF_WELCOME = "WELCOME";
    localparam [95:0] REF_SETTINGS = "SETTINGS";
    localparam [95:0] REF_INSTRUCTIONS = "INSTRUCTIONS";
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] pixel_y = 10'd0;
    reg active_video = 1'b1;
    reg [1:0] mode = 2'd0;
    wire panel_on, accent_on, text_on;
    monitor_menu_overlay dut (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .mode(mode), .panel_on(panel_on),
        .accent_on(accent_on), .text_on(text_on)
    );

    reg [6:0] ref_ch = 7'h20;
    reg [2:0] ref_col = 3'd0;
    wire [7:0] ref_data;
    font_rom ref_font (.clk(clk), .ch(ref_ch), .col(ref_col), .data(ref_data));

    integer x, y, page, cell_index, glyph_col, glyph_row;
    integer title_origin, title_length;
    reg [95:0] title_reference;
    reg expected_pixel;
    integer errors = 0;
    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        for (page = 0; page < 3; page = page + 1) begin
            case (page)
                0: begin title_origin=152; title_length=7; title_reference=REF_WELCOME; end
                1: begin title_origin=128; title_length=8; title_reference=REF_SETTINGS; end
                default: begin title_origin=32; title_length=12; title_reference=REF_INSTRUCTIONS; end
            endcase
            mode = page;
            for (y = 180; y < 236; y = y + 1) begin
                for (x = title_origin; x < title_origin + title_length * 48; x = x + 1) begin
                    @(negedge clk);
                    pixel_x = x;
                    pixel_y = y;
                    cell_index = (x - title_origin) / 48;
                    glyph_col = ((x - title_origin) % 48) / 8;
                    glyph_row = (y - 180) / 8;
                    ref_ch = title_reference[(title_length - 1 - cell_index) * 8 +: 7];
                    ref_col = glyph_col;
                    @(posedge clk); #1;
                    expected_pixel = (glyph_col < 5) && ref_data[glyph_row];
                    if (text_on !== expected_pixel) begin
                        $display("FAIL title raster page=%0d x=%0d y=%0d got=%b expected=%b",
                                 page, x, y, text_on, expected_pixel);
                        errors = errors + 1;
                    end
                end
            end
        end

        // Compare the entire small-text raster with an independent character
        // walk of the requested Welcome line, including spacing columns.
        mode = 2'd0;
        for (y = 322; y < 336; y = y + 1) begin
            for (x = 212; x < 428; x = x + 1) begin
                @(negedge clk);
                pixel_x = x;
                pixel_y = y;
                cell_index = (x - 212) / 12;
                glyph_col = ((x - 212) % 12) / 2;
                glyph_row = (y - 322) / 2;
                ref_ch = EXPECTED_LINE[(17 - cell_index) * 8 +: 7];
                ref_col = glyph_col;
                @(posedge clk); #1;
                expected_pixel = (glyph_col < 5) && ref_data[glyph_row];
                if (text_on !== expected_pixel) begin
                    $display("FAIL menu overlay at x=%0d y=%0d got=%b expected=%b",
                             x, y, text_on, expected_pixel);
                    errors = errors + 1;
                end
            end
        end
        if (errors != 0) $fatal(1, "monitor menu overlay text mismatch: %0d", errors);
        $display("PASS: Welcome page renders U/D = SELECT STAGE at the expected small-text position");
        $finish;
    end
endmodule
