`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Whole-second elapsed timer for the current maze. The counter advances only
// in PLAY, freezes in WIN, and clears when physics initializes a new maze.
// Minutes saturate at 99 so the fixed-width OLED display never wraps around.
module game_timer #(
    parameter integer CLK_HZ = 100_000_000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [`GAME_STATE_W-1:0] game_state,
    input  wire       phys_init,
    output reg  [7:0] elapsed_minutes_bcd = 8'h00,
    output reg  [7:0] elapsed_seconds_bcd = 8'h00
);
    localparam integer COUNT_WIDTH = (CLK_HZ > 1) ? $clog2(CLK_HZ) : 1;

    reg [COUNT_WIDTH-1:0] subsecond_count = {COUNT_WIDTH{1'b0}};
    reg timer_full = 1'b0;

    always @(posedge clk) begin
        if (rst || phys_init) begin
            subsecond_count     <= {COUNT_WIDTH{1'b0}};
            elapsed_minutes_bcd <= 8'h00;
            elapsed_seconds_bcd <= 8'h00;
            timer_full          <= 1'b0;
        end else if ((game_state == `ST_PLAY) && !timer_full) begin
            if ((CLK_HZ <= 1) || (subsecond_count == CLK_HZ - 1)) begin
                subsecond_count <= {COUNT_WIDTH{1'b0}};

                if (elapsed_seconds_bcd == 8'h59) begin
                    if (elapsed_minutes_bcd == 8'h99) begin
                        timer_full <= 1'b1;
                    end else begin
                        elapsed_seconds_bcd <= 8'h00;
                        if (elapsed_minutes_bcd[3:0] == 4'd9)
                            elapsed_minutes_bcd <= {
                                elapsed_minutes_bcd[7:4] + 4'd1, 4'd0
                            };
                        else
                            elapsed_minutes_bcd[3:0] <=
                                elapsed_minutes_bcd[3:0] + 4'd1;
                    end
                end else if (elapsed_seconds_bcd[3:0] == 4'd9) begin
                    elapsed_seconds_bcd <= {
                        elapsed_seconds_bcd[7:4] + 4'd1, 4'd0
                    };
                end else begin
                    elapsed_seconds_bcd[3:0] <=
                        elapsed_seconds_bcd[3:0] + 4'd1;
                end
            end else begin
                subsecond_count <= subsecond_count + 1'b1;
            end
        end else begin
            // Discard a partial second while paused or generating a maze.
            subsecond_count <= {COUNT_WIDTH{1'b0}};
        end
    end
endmodule
