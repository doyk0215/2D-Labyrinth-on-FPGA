`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Stage countdown, loaded on phys_init and advanced only in PLAY.
// Legacy elapsed_* names now carry TIME LEFT for existing OLED/render wiring.
module game_timer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer EASY_SECONDS = 60,
    parameter integer HARD_SECONDS = 120,
    parameter integer HUGE_SECONDS = 180
) (
    input wire clk,
    input wire rst,
    input wire maze_pixel_visible,
    input wire [`GAME_STATE_W-1:0] game_state,
    input wire phys_init,
    input wire [3:0] n_cells,
    output reg [7:0] elapsed_minutes_bcd = 8'h00,
    output reg [7:0] elapsed_seconds_bcd = 8'h00,
    output wire time_up
);
    localparam integer COUNT_WIDTH = (CLK_HZ > 1) ? $clog2(CLK_HZ) : 1;
    reg [COUNT_WIDTH-1:0] subsecond_count = {COUNT_WIDTH{1'b0}};

    // Constant evaluation only: no runtime division/modulo datapath.
    // Clamp parameter values to the display's 99:59 cap.
    function [15:0] limit_bcd;
        input integer seconds;
        integer bounded, minutes, remainder;
        begin
            bounded = (seconds < 0) ? 0 : (seconds > 5999) ? 5999 : seconds;
            minutes = bounded / 60;
            remainder = bounded % 60;
            limit_bcd[15:12] = minutes / 10;
            limit_bcd[11:8] = minutes % 10;
            limit_bcd[7:4] = remainder / 10;
            limit_bcd[3:0] = remainder % 10;
        end
    endfunction
    localparam [15:0] EASY_LIMIT = limit_bcd(EASY_SECONDS);
    localparam [15:0] HARD_LIMIT = limit_bcd(HARD_SECONDS);
    localparam [15:0] HUGE_LIMIT = limit_bcd(HUGE_SECONDS);
    reg play_started = 1'b0;
    wire timer_running = (game_state == `ST_PLAY) && play_started;
    wire empty = ({elapsed_minutes_bcd, elapsed_seconds_bcd} == 16'h0000);
    wire second_tick = (CLK_HZ <= 1) || (subsecond_count == CLK_HZ - 1);
    // Include the edge that decrements 00:01 to zero. If frame_tick/in_goal
    // coincides with that edge, the deadline wins rather than a zero-time WIN.
    assign time_up = !rst && !phys_init && (empty ||
                     (timer_running && second_tick &&
                      ({elapsed_minutes_bcd, elapsed_seconds_bcd} == 16'h0001)));

    always @(posedge clk) begin
        if (rst) begin
            subsecond_count <= {COUNT_WIDTH{1'b0}};
            play_started <= 1'b0;
            elapsed_minutes_bcd <= 8'h00;
            elapsed_seconds_bcd <= 8'h00;
        end else if (phys_init) begin
            subsecond_count <= {COUNT_WIDTH{1'b0}};
            play_started <= 1'b0;
            case (n_cells)
                4'd5: {elapsed_minutes_bcd, elapsed_seconds_bcd} <= EASY_LIMIT;
                4'd15: {elapsed_minutes_bcd, elapsed_seconds_bcd} <= HUGE_LIMIT;
                default: {elapsed_minutes_bcd, elapsed_seconds_bcd} <= HARD_LIMIT;
            endcase
        end else if (game_state == `ST_PLAY) begin
            // Arm only when a PLAY pixel is actually being sent to the
            // display. Generation completion and the renderer's frame
            // snapshot both happen during vertical blanking, before the maze
            // is visible on the screen.
            if (maze_pixel_visible)
                play_started <= 1'b1;

            if (!play_started || empty) begin
                subsecond_count <= {COUNT_WIDTH{1'b0}};
            end else if (second_tick) begin
                subsecond_count <= {COUNT_WIDTH{1'b0}};
                if (elapsed_seconds_bcd == 8'h00) begin
                    elapsed_seconds_bcd <= 8'h59;
                    if (elapsed_minutes_bcd[3:0] == 4'd0)
                        elapsed_minutes_bcd <= {elapsed_minutes_bcd[7:4] - 4'd1, 4'd9};
                    else
                        elapsed_minutes_bcd[3:0] <= elapsed_minutes_bcd[3:0] - 4'd1;
                end else if (elapsed_seconds_bcd[3:0] == 4'd0) begin
                    elapsed_seconds_bcd <= {elapsed_seconds_bcd[7:4] - 4'd1, 4'd9};
                end else begin
                    elapsed_seconds_bcd[3:0] <= elapsed_seconds_bcd[3:0] - 4'd1;
                end
            end else begin
                subsecond_count <= subsecond_count + 1'b1;
            end
        end else begin
            subsecond_count <= {COUNT_WIDTH{1'b0}};
            play_started <= 1'b0;
        end
    end
endmodule
