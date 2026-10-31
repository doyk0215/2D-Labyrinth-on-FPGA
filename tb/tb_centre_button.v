`timescale 1ns / 1ps

module tb_centre_button;
    reg clk = 0, rst = 1, button = 0;
    always #5 clk = ~clk;
    wire short_press, full_reset;
    centre_button #(.DEBOUNCE_CYCLES(3), .LONG_PRESS_CYCLES(12)) dut (
        .clk(clk), .por_reset(rst), .level_in(button),
        .short_press(short_press), .full_reset(full_reset)
    );
    // Exercise the minimum legal parameter values as well as normal counters.
    wire quick_short, quick_reset;
    centre_button #(.DEBOUNCE_CYCLES(1), .LONG_PRESS_CYCLES(1)) quick_i (
        .clk(clk), .por_reset(rst), .level_in(button),
        .short_press(quick_short), .full_reset(quick_reset)
    );
    integer short_count = 0, reset_count = 0;
    reg was_reset = 0;
    always @(negedge clk) begin
        if (short_press) short_count = short_count + 1;
        if (full_reset && !was_reset) reset_count = reset_count + 1;
        was_reset = full_reset;
        if ((short_press && full_reset) || quick_short)
            fail("short and long actions overlapped, or one-cycle hold fired short");
    end
    task fail;
        input [511:0] message;
        begin $display("FAIL centre button: %0s", message); $fatal(1); end
    endtask
    task cycles;
        input integer count;
        begin repeat (count) @(posedge clk); #1; end
    endtask
    task short_click;
        begin
            @(negedge clk); button = 1;
            cycles(8);
            if (short_press || full_reset) fail("short hold acted before release");
            @(negedge clk); button = 0;
            cycles(10);
        end
    endtask
    initial begin
        cycles(4); rst = 0;
        // Contact bounce shorter than the debounce window produces no action.
        @(negedge clk); button = 1;
        cycles(1); button = 0;
        cycles(1); button = 1;
        cycles(2); button = 0;
        cycles(10);
        if (short_count || reset_count) fail("bounce generated a button action");
        short_click();
        short_click();
        if (short_count != 2 || reset_count) fail("short holds accumulated or failed to re-arm");

        @(negedge clk); button = 1;
        cycles(16);
        if (full_reset || short_count != 2) fail("long threshold fired early");
        cycles(4);
        if (!full_reset || !quick_reset) fail("continuous hold did not assert reset");
        cycles(80);
        if (!full_reset || short_count != 2 || reset_count != 1)
            fail("held reset repeated, wrapped, or fired a short action");
        @(negedge clk); button = 0;
        cycles(10);
        if (full_reset || quick_reset || short_count != 2) fail("long release fired short or retained reset");
        short_click();
        if (short_count != 3 || reset_count != 1) fail("short action did not re-arm after long reset");

        // A button held through POR must not create a confirm on reset release.
        rst = 1; button = 1;
        cycles(4); rst = 0;
        cycles(24);
        if (!full_reset || short_count != 3) fail("held-at-power-on button confirmed a stage");
        button = 0; cycles(10);
        if (short_count != 3) fail("held-at-power-on release fired short");
        $display("PASS: centre button debounce, release-only short, exclusive long reset, re-arm, and minimum parameters");
        $finish;
    end
    initial begin #100000; fail("timeout"); end
endmodule
