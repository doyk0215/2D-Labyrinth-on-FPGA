`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_game_timer;
    localparam integer CLK_HZ = 4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [`GAME_STATE_W-1:0] game_state = `ST_GENERATE;
    reg phys_init = 1'b0;
    wire [7:0] elapsed_minutes_bcd;
    wire [7:0] elapsed_seconds_bcd;
    integer errors = 0;
    integer i;

    always #5 clk = ~clk;

    game_timer #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst(rst), .game_state(game_state), .phys_init(phys_init),
        .elapsed_minutes_bcd(elapsed_minutes_bcd),
        .elapsed_seconds_bcd(elapsed_seconds_bcd)
    );

    task check_time;
        input [7:0] expected_minutes;
        input [7:0] expected_seconds;
        input [255:0] label_text;
        begin
            if (elapsed_minutes_bcd !== expected_minutes ||
                elapsed_seconds_bcd !== expected_seconds) begin
                $display("FAIL tb_game_timer %0s: got %02h:%02h expected %02h:%02h",
                         label_text, elapsed_minutes_bcd, elapsed_seconds_bcd,
                         expected_minutes, expected_seconds);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;
        repeat (12) @(posedge clk);
        #1 check_time(8'h00, 8'h00, "does not count during generation");

        game_state = `ST_PLAY;
        repeat (CLK_HZ - 1) @(posedge clk);
        #1 check_time(8'h00, 8'h00, "waits for one full second");
        @(posedge clk);
        #1 check_time(8'h00, 8'h01, "counts one second in PLAY");

        game_state = `ST_WIN;
        repeat (CLK_HZ * 3) @(posedge clk);
        #1 check_time(8'h00, 8'h01, "freezes in WIN");

        game_state = `ST_PLAY;
        repeat (CLK_HZ - 1) @(posedge clk);
        #1 check_time(8'h00, 8'h01, "does not carry a partial paused second");
        @(posedge clk);
        #1 check_time(8'h00, 8'h02, "resumes whole-second counting");

        @(negedge clk); phys_init = 1'b1;
        @(posedge clk); #1;
        phys_init = 1'b0;
        check_time(8'h00, 8'h00, "clears on new maze initialization");
        repeat (CLK_HZ) @(posedge clk);
        #1 check_time(8'h00, 8'h01, "counts the new maze from zero");

        rst = 1'b1;
        @(posedge clk); #1;
        rst = 1'b0;
        check_time(8'h00, 8'h00, "clears on reset");

        game_state = `ST_PLAY;
        for (i = 0; i < 5999 * CLK_HZ; i = i + 1)
            @(posedge clk);
        #1 check_time(8'h99, 8'h59, "saturates at 99:59");
        repeat (CLK_HZ * 2) @(posedge clk);
        #1 check_time(8'h99, 8'h59, "does not wrap after saturation");

        if (errors == 0)
            $display("PASS: game_timer PLAY count, WIN freeze, clear, BCD, and 99:59 saturation");
        else
            $display("FAIL: game_timer had %0d errors", errors);
        $finish;
    end
endmodule
