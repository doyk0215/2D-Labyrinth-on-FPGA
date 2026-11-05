`timescale 1ns / 1ps

module tb_brick_wall_pixel;
    `include "brick_wall_model.vh"
    reg [5:0] maze_x = 0, maze_y = 0;
    wire [11:0] rgb;
    integer x, y, frame_file;
    brick_wall_pixel dut (.maze_x(maze_x), .maze_y(maze_y), .rgb(rgb));
    initial begin
        frame_file = $fopen("brick_swatch.ppm", "w");
        if (!frame_file) begin $display("FAIL: cannot open brick swatch"); $finish; end
        $fwrite(frame_file, "P3\n64 64\n255\n");
        for (y = 0; y < 64; y = y + 1)
            for (x = 0; x < 64; x = x + 1) begin
                maze_x = x; maze_y = y; #1;
                if (rgb !== brick_wall_model(x, y)) begin
                    $display("FAIL: brick texture at (%0d,%0d): got %h", x, y, rgb);
                    $finish;
                end
                $fwrite(frame_file, "%0d %0d %0d\n", rgb[11:8]*17, rgb[7:4]*17, rgb[3:0]*17);
            end
        $fclose(frame_file);
        // The pattern must repeat at distant world coordinates, including the
        // last N=20 map pixel. The hardware intentionally receives only bits 5:0.
        for (y = 0; y < 656; y = y + 1)
            for (x = 0; x < 656; x = x + 1) begin
                maze_x = x; maze_y = y; #1;
                if (rgb !== brick_wall_model(x, y)) begin
                    $display("FAIL: distant brick texture at (%0d,%0d)", x, y);
                    $finish;
                end
            end
        $display("PASS: brick texture matches approved integer model across all 656x656 world pixels");
        $finish;
    end
endmodule
