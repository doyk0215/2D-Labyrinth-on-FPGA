`timescale 1ns / 1ps

// CENTER has mutually exclusive actions: short press on debounced release,
// or full reset after a continuous hold. Keep this detector outside the reset
// it generates, so holding/releasing reset cannot produce a confirm event.
module centre_button #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer LONG_PRESS_CYCLES = 200_000_000
) (
    input wire clk,
    input wire por_reset,
    input wire level_in,
    output reg short_press = 1'b0,
    output reg full_reset = 1'b0
);
    localparam integer DEBOUNCE_W = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam integer HOLD_W = (LONG_PRESS_CYCLES > 1) ? $clog2(LONG_PRESS_CYCLES) : 1;
    (* ASYNC_REG = "TRUE" *) reg [1:0] level_sync = 2'b00;
    reg debounced_level = 1'b0;
    reg [DEBOUNCE_W-1:0] stable_count = 0;
    reg [HOLD_W-1:0] hold_count = 0;
    reg pressed = 1'b0;

    always @(posedge clk) begin
        if (por_reset) begin
            level_sync <= 2'b00;
            debounced_level <= 1'b0;
            stable_count <= 0;
        end else begin
            level_sync <= {level_sync[0], level_in};
            if (level_sync[1] == debounced_level) begin
                stable_count <= 0;
            end else if ((DEBOUNCE_CYCLES <= 1) || (stable_count == DEBOUNCE_CYCLES - 1)) begin
                debounced_level <= level_sync[1];
                stable_count <= 0;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (por_reset) begin
            short_press <= 1'b0;
            full_reset <= 1'b0;
            pressed <= 1'b0;
            hold_count <= 0;
        end else begin
            short_press <= 1'b0;
            if (!debounced_level) begin
                short_press <= pressed && !full_reset;
                pressed <= 1'b0;
                full_reset <= 1'b0;
                hold_count <= 0;
            end else begin
                pressed <= 1'b1;
                if (!full_reset) begin
                    if ((LONG_PRESS_CYCLES <= 1) || (hold_count == LONG_PRESS_CYCLES - 1))
                        full_reset <= 1'b1;
                    else
                        hold_count <= hold_count + 1'b1;
                end
            end
        end
    end
endmodule
