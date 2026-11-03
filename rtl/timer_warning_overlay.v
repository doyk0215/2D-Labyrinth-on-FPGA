`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Difficulty-independent late-game warning for the VGA output. The edge
// strength is derived only from absolute time remaining, while the visible
// pulse runs at 2 Hz and the timer color changes once per second.
module timer_warning_overlay #(
    parameter integer FRAMES_PER_HALF_SECOND = 30
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   frame_tick,
    input  wire [9:0]             pixel_x,
    input  wire [9:0]             pixel_y,
    input  wire                   active_video,
    input  wire [`GAME_STATE_W-1:0] game_state,
    input  wire [7:0]             minutes_bcd,
    input  wire [7:0]             seconds_bcd,
    output wire                   warning_active,
    output reg                    timer_flash_red = 1'b0,
    output reg                    edge_glow = 1'b0,
    output reg  [3:0]             edge_strength = 4'd0
);
    localparam integer HALF_COUNT_WIDTH =
        (FRAMES_PER_HALF_SECOND > 1) ? $clog2(FRAMES_PER_HALF_SECOND * 2) : 1;

    wire time_at_or_below_30 = (minutes_bcd == 8'h00) &&
                               (seconds_bcd <= 8'h30);
    wire time_is_zero = (minutes_bcd == 8'h00) && (seconds_bcd == 8'h00);
    wire warning_in_play = (game_state == `ST_PLAY) && time_at_or_below_30;
    wire warning_at_time_up = (game_state == `ST_LOSE) && time_is_zero;
    assign warning_active = warning_in_play || warning_at_time_up;

    reg [HALF_COUNT_WIDTH-1:0] frame_count = {HALF_COUNT_WIDTH{1'b0}};
    reg pulse_phase = 1'b0;

    always @(posedge clk) begin
        if (rst || !warning_in_play) begin
            frame_count <= {HALF_COUNT_WIDTH{1'b0}};
            pulse_phase <= 1'b0;
            timer_flash_red <= 1'b0;
        end else if (frame_tick) begin
            if (frame_count == FRAMES_PER_HALF_SECOND - 1) begin
                frame_count <= frame_count + 1'b1;
                pulse_phase <= ~pulse_phase;
            end else if (frame_count == (FRAMES_PER_HALF_SECOND * 2) - 1) begin
                frame_count <= {HALF_COUNT_WIDTH{1'b0}};
                pulse_phase <= ~pulse_phase;
                timer_flash_red <= ~timer_flash_red;
            end else begin
                frame_count <= frame_count + 1'b1;
            end
        end
    end

    // Convert the BCD seconds field to binary with shifts and additions. The
    // warning window guarantees a value from 0 through 30.
    wire [5:0] seconds_tens = {2'b00, seconds_bcd[7:4]};
    wire [5:0] seconds_ones = {2'b00, seconds_bcd[3:0]};
    wire [5:0] seconds_left = (seconds_tens << 3) + (seconds_tens << 1) + seconds_ones;
    wire [4:0] seconds_elapsed = 6'd30 - seconds_left;
    wire [4:0] ramp_candidate = {1'b0, seconds_elapsed[4:1]} + 5'd1;
    wire [3:0] ramp_level = (ramp_candidate > 5'd15) ? 4'd15 : ramp_candidate[3:0];

    wire edge_inner = (pixel_x < 10'd4) || (pixel_x >= 10'd636) ||
                      (pixel_y < 10'd4) || (pixel_y >= 10'd476);
    wire edge_middle = (pixel_x < 10'd8) || (pixel_x >= 10'd632) ||
                       (pixel_y < 10'd8) || (pixel_y >= 10'd472);
    wire edge_outer = (pixel_x < 10'd12) || (pixel_x >= 10'd628) ||
                      (pixel_y < 10'd12) || (pixel_y >= 10'd468);
    wire [3:0] middle_strength = {1'b0, ramp_level[3:1]} + ramp_level[0];
    wire [3:0] outer_strength = {2'b00, ramp_level[3:2]} +
                                (|ramp_level[1:0]);
    wire [3:0] spatial_strength = edge_inner ? ramp_level :
                                  edge_middle ? middle_strength :
                                  edge_outer ? outer_strength : 4'd0;
    wire edge_pulse_on = (warning_in_play && pulse_phase) || warning_at_time_up;
    wire [3:0] edge_strength_now = (edge_pulse_on && active_video) ?
                                   spatial_strength : 4'd0;

    always @(posedge clk) begin
        if (rst) begin
            edge_glow <= 1'b0;
            edge_strength <= 4'd0;
        end else begin
            edge_strength <= edge_strength_now;
            edge_glow <= (edge_strength_now != 0);
        end
    end
endmodule
