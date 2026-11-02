`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Stage countdown, loaded on phys_init and advanced only in PLAY.
// Legacy elapsed_* names now carry TIME LEFT for existing OLED/render wiring.
module game_timer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer EASY_SECONDS = 60,
    parameter integer HARD_SECONDS = 120,
    parameter integer HUGE_SECONDS = 180,
    parameter integer BONUS_SECONDS = 10
) (
    input wire clk,
    input wire rst,
    input wire maze_pixel_visible,
    input wire player_action,
    input wire time_bonus_pulse,
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
    localparam [15:0] BONUS_BCD = limit_bcd(BONUS_SECONDS);
    function [15:0] decrement_bcd;
        input [15:0] value;
        begin
            decrement_bcd=value;
            if(value != 0) begin
                if(value[3:0] != 0) decrement_bcd[3:0]=value[3:0]-1'b1;
                else begin
                    decrement_bcd[3:0]=9;
                    if(value[7:4] != 0) decrement_bcd[7:4]=value[7:4]-1'b1;
                    else begin
                        decrement_bcd[7:4]=5;
                        if(value[11:8] != 0) decrement_bcd[11:8]=value[11:8]-1'b1;
                        else begin
                            decrement_bcd[11:8]=9;
                            decrement_bcd[15:12]=value[15:12]-1'b1;
                        end
                    end
                end
            end
        end
    endfunction
    // Mixed-radix BCD ripple: seconds tens carries at six, all other
    // digits at ten. No runtime division, modulo or DSP multiplier.
    function [15:0] add_bonus_bcd;
        input [15:0] value;
        reg [4:0] digit;
        reg carry;
        reg [15:0] result;
        begin
            digit={1'b0,value[3:0]}+{1'b0,BONUS_BCD[3:0]};
            carry=digit>=10; result[3:0]=carry ? digit-5'd10 : digit;
            digit={1'b0,value[7:4]}+{1'b0,BONUS_BCD[7:4]}+carry;
            carry=digit>=6; result[7:4]=carry ? digit-5'd6 : digit;
            digit={1'b0,value[11:8]}+{1'b0,BONUS_BCD[11:8]}+carry;
            carry=digit>=10; result[11:8]=carry ? digit-5'd10 : digit;
            digit={1'b0,value[15:12]}+{1'b0,BONUS_BCD[15:12]}+carry;
            result[15:12]=digit;
            add_bonus_bcd=(digit>=10) ? 16'h9959 : result;
        end
    endfunction
    reg play_started = 1'b0;
    wire timer_running = (game_state == `ST_PLAY) && play_started;
    wire empty = ({elapsed_minutes_bcd, elapsed_seconds_bcd} == 16'h0000);
    wire second_tick = (CLK_HZ <= 1) || (subsecond_count == CLK_HZ - 1);
    wire bonus_now = game_state == `ST_PLAY && time_bonus_pulse && BONUS_BCD != 0;
    wire decrement_now = timer_running && !empty && second_tick;
    wire [15:0] time_before_bonus = decrement_now ?
        decrement_bcd({elapsed_minutes_bcd,elapsed_seconds_bcd}) :
        {elapsed_minutes_bcd,elapsed_seconds_bcd};
    // Include the edge that decrements 00:01 to zero. If frame_tick/in_goal
    // coincides with that edge, the deadline wins rather than a zero-time WIN.
    assign time_up = !rst && !phys_init && !bonus_now && (empty ||
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
            if (maze_pixel_visible && player_action)
                play_started <= 1'b1;

            if (bonus_now)
                {elapsed_minutes_bcd,elapsed_seconds_bcd} <= add_bonus_bcd(time_before_bonus);

            if (!play_started || empty) begin
                subsecond_count <= {COUNT_WIDTH{1'b0}};
            end else if (second_tick) begin
                subsecond_count <= {COUNT_WIDTH{1'b0}};
                if(!bonus_now)
                    {elapsed_minutes_bcd,elapsed_seconds_bcd} <= time_before_bonus;
            end else begin
                subsecond_count <= subsecond_count + 1'b1;
            end
        end else begin
            subsecond_count <= {COUNT_WIDTH{1'b0}};
            play_started <= 1'b0;
        end
    end
endmodule
