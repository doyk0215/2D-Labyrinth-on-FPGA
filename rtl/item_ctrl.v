`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Sole writer of item visibility, active effect and countdown. Position is
// sampled on phys_done, after the ball's new centre is committed in blanking.
// Respawn eligibility may expire at any clock; visibility changes only on a
// physics completion, so active VGA frames never mix hidden/visible boxes.
module item_ctrl #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer EFFECT_SECONDS = 8,
    // Per-effect durations; each defaults to EFFECT_SECONDS.
    parameter integer LOW_GRAV_SECONDS = EFFECT_SECONDS,
    parameter integer INVINCIBLE_SECONDS = EFFECT_SECONDS,
    parameter integer REVERSE_GRAV_SECONDS = EFFECT_SECONDS,
    parameter integer HIGH_GRAV_SECONDS = EFFECT_SECONDS,
    parameter integer ZERO_GRAV_SECONDS = EFFECT_SECONDS,
    parameter integer INVERT_SECONDS = EFFECT_SECONDS,
    parameter integer FOG_SECONDS = EFFECT_SECONDS,
    parameter integer RESPAWN_SECONDS = 15,
    parameter STUB_LOW_ONLY = 1'b0,
    parameter DEFER_EFFECT = 1'b0
) (
    input wire clk,
    input wire rst,
    input wire [`GAME_STATE_W-1:0] game_state,
    input wire phys_init,
    input wire phys_done,
    input wire [`N_CELLS_W-1:0] n_cells,
    input wire signed [`POS_W-1:0] ball_x,
    input wire signed [`POS_W-1:0] ball_y,
    input wire [8*`COORD_W-1:0] box_cols,
    input wire [8*`COORD_W-1:0] box_rows,
    input wire [7:0] box_valid,
    input wire [31:0] seed,
    input wire roulette_busy,
    input wire roulette_commit,
    output reg [7:0] box_visible,
    output reg [`ITEM_EFFECT_W-1:0] active_effect,
    output reg [6:0] effect_seconds,
    output reg pickup_pulse,
    output reg [2:0] pickup_index,
    output reg [`ITEM_EFFECT_W-1:0] pickup_effect,
    output reg debuff_blocked,
    output wire time_bonus_pulse,
    output wire wall_breaker_pulse,
    output reg pending_valid,
    output reg [`ITEM_EFFECT_W-1:0] pending_effect
);
    localparam integer SECOND_W = (CLK_HZ > 1) ? $clog2(CLK_HZ) : 1;
    function [6:0] clamp_seconds;
        input integer s;
        clamp_seconds = (s < 0) ? 7'd0 : (s > 99) ? 7'd99 : s;
    endfunction
    // Constant table: the time bonus and unknown codes have no duration.
    function [6:0] duration_of;
        input [`ITEM_EFFECT_W-1:0] code;
        case(code)
            `ITEM_LOW_GRAV:     duration_of = clamp_seconds(LOW_GRAV_SECONDS);
            `ITEM_INVINCIBLE:   duration_of = clamp_seconds(INVINCIBLE_SECONDS);
            `ITEM_REVERSE_GRAV: duration_of = clamp_seconds(REVERSE_GRAV_SECONDS);
            `ITEM_HIGH_GRAV:    duration_of = clamp_seconds(HIGH_GRAV_SECONDS);
            `ITEM_ZERO_GRAV:    duration_of = clamp_seconds(ZERO_GRAV_SECONDS);
            `ITEM_INVERT:       duration_of = clamp_seconds(INVERT_SECONDS);
            `ITEM_FOG:          duration_of = clamp_seconds(FOG_SECONDS);
            default:            duration_of = 7'd0;
        endcase
    endfunction
    localparam [63:0] RESPAWN_CYCLES = 64'd1 * ((CLK_HZ > 0) ? CLK_HZ : 1) *
                                     ((RESPAWN_SECONDS > 0) ? RESPAWN_SECONDS : 0);
    localparam integer RESPAWN_W = (RESPAWN_CYCLES > 1) ? $clog2(RESPAWN_CYCLES+1) : 1;
    reg [SECOND_W-1:0] effect_subsecond;
    reg [RESPAWN_W-1:0] respawn_left [0:7];

    reg [31:0] rng;
    reg [1:0] buff_roll;
    reg [2:0] debuff_roll;
    function [31:0] xorshift;
        input [31:0] value;
        reg [31:0] a,b;
        begin a=value^(value<<13); b=a^(a>>17); xorshift=b^(b<<5); end
    endfunction
    wire [31:0] initial_rng = (seed ^ 32'h9e3779b9) == 0 ? 32'h1 : seed ^ 32'h9e3779b9;

    // Full signed intermediate is essential near negative map edges and N=20.
    wire signed [18:0] centre = ($signed({{(19-`N_CELLS_W){1'b0}},n_cells}) <<< `TILE_SHIFT) + 19'sd2048;
    wire signed [18:0] absolute_x = $signed({ball_x[17],ball_x}) + centre;
    wire signed [18:0] absolute_y = $signed({ball_y[17],ball_y}) + centre;
    wire [`COORD_W-1:0] ball_col = absolute_x[`TILE_SHIFT+`COORD_W-1:`TILE_SHIFT];
    wire [`COORD_W-1:0] ball_row = absolute_y[`TILE_SHIFT+`COORD_W-1:`TILE_SHIFT];
    // A valid tile is 0..2*N inclusive. Checking the signed high bit and the
    // already-extracted tile coordinates avoids a second wide arithmetic
    // shift/compare path in the pickup and respawn countdown enables.
    wire [`COORD_W-1:0] max_tile_coord = {n_cells, 1'b0};
    wire in_map = !absolute_x[18] && !absolute_y[18] &&
                  ball_col <= max_tile_coord && ball_row <= max_tile_coord;
    reg [7:0] on_box;
    reg hit_valid;
    reg [2:0] hit_index;
    reg [`ITEM_EFFECT_W-1:0] rolled_effect;
    wire [6:0] pending_duration = duration_of(pending_effect);
    wire [6:0] rolled_duration = duration_of(rolled_effect);
    wire [2:0] buff_count = (n_cells <= 5'd6) ? 3'd0 :
                            (n_cells <= 5'd8) ? 3'd1 :
                            (n_cells == 20) ? 3'd4 :
                            (n_cells >= 15) ? 3'd3 : 3'd2;
    wire pickup_allowed = !DEFER_EFFECT || (!roulette_busy && !pending_valid);
    wire pickup_now = !rst && !phys_init && game_state == `ST_PLAY && phys_done && hit_valid && pickup_allowed;
    wire block_debuff = active_effect == `ITEM_INVINCIBLE && effect_seconds != 0 && hit_index >= buff_count;
    // Same-edge grant: registering this through pickup_pulse would lose a
    // pickup coincident with the timer's terminal edge. Immediate grants are
    // consumed with visibility; deferred grants clear the held pending item.
    wire commit_now = DEFER_EFFECT && pending_valid && roulette_commit &&
                      !rst && !phys_init && game_state == `ST_PLAY;
    assign time_bonus_pulse = DEFER_EFFECT ? (commit_now && pending_effect == `ITEM_TIME_BONUS) :
                             (pickup_now && !block_debuff && rolled_effect == `ITEM_TIME_BONUS);
    // Same grant edge as the time bonus: the breaker is instant and never
    // becomes active_effect, so it cannot end or refresh a running effect.
    assign wall_breaker_pulse = DEFER_EFFECT ? (commit_now && pending_effect == `ITEM_WALL_BREAKER) :
                                (pickup_now && !block_debuff && rolled_effect == `ITEM_WALL_BREAKER);
    integer k;
    always @* begin
        for(k=0;k<8;k=k+1)
            on_box[k] = in_map && box_valid[k] &&
                        ball_col == box_cols[k*`COORD_W+:`COORD_W] && ball_row == box_rows[k*`COORD_W+:`COORD_W];
        hit_valid=0; hit_index=0;
        // Lowest slot wins if a malformed map overlaps boxes. At most one
        // pickup is published per completed physics frame.
        for(k=7;k>=0;k=k-1) begin
            if(on_box[k] && box_visible[k]) begin hit_valid=1; hit_index=k; end
        end
        if(STUB_LOW_ONLY) rolled_effect=`ITEM_LOW_GRAV;
        else if(hit_index < buff_count)
            rolled_effect=(buff_roll == 2'd3) ? `ITEM_WALL_BREAKER : {2'b0,buff_roll};
        else rolled_effect=4'd3+{1'b0,debuff_roll};
    end
    integer i;
    always @(posedge clk) begin
        pickup_pulse<=0; debuff_blocked<=0;
        if(rst) begin
            box_visible<=0; active_effect<=`ITEM_NONE; effect_seconds<=0;
            effect_subsecond<=0; pickup_index<=0; pickup_effect<=`ITEM_NONE;
            rng<=32'h1; buff_roll<=0; debuff_roll<=0;
            pending_valid<=0; pending_effect<=`ITEM_NONE;
            for(i=0;i<8;i=i+1) respawn_left[i]<=0;
        end else if(phys_init) begin
            box_visible<=box_valid; active_effect<=`ITEM_NONE; effect_seconds<=0;
            effect_subsecond<=0; pickup_index<=0; pickup_effect<=`ITEM_NONE;
            rng<=initial_rng; buff_roll<=0; debuff_roll<=0;
            pending_valid<=0; pending_effect<=`ITEM_NONE;
            for(i=0;i<8;i=i+1) respawn_left[i]<=0;
        end else if(game_state == `ST_PAUSED) begin
            // Preserve effects, respawn timers, and box visibility for Resume.
        end else if(game_state != `ST_PLAY) begin
            active_effect<=`ITEM_NONE; effect_seconds<=0; effect_subsecond<=0;
            pickup_effect<=`ITEM_NONE;
            pending_valid<=0; pending_effect<=`ITEM_NONE;
            for(i=0;i<6;i=i+1) respawn_left[i]<=0;
            // Preserve the frozen result picture in WIN/LOSE. New mazes and
            // MENU/GENERATE clear visibility before phys_init reloads it.
            if(game_state != `ST_WIN && game_state != `ST_LOSE) box_visible<=0;
        end else begin
            rng<=xorshift(rng);
            // Rejection sampling caches valid choices between frames, with
            // no modulo/divider on the pickup path and no out-of-pool IDs.
            buff_roll<=rng[1:0];     // four buffs, so every 2-bit value is valid
            if(rng[5:3] < 5) debuff_roll<=rng[5:3];
            if(active_effect != `ITEM_NONE && effect_seconds != 0) begin
                if(CLK_HZ <= 1 || effect_subsecond == CLK_HZ-1) begin
                    effect_subsecond<=0;
                    effect_seconds<=effect_seconds-1'b1;
                    if(effect_seconds == 1) active_effect<=`ITEM_NONE;
                end else effect_subsecond<=effect_subsecond+1'b1;
            end else effect_subsecond<=0;
            for(i=0;i<8;i=i+1) begin
                if(respawn_left[i] != 0) respawn_left[i]<=respawn_left[i]-1'b1;
                if(phys_done && !box_visible[i] && box_valid[i] &&
                   respawn_left[i] == 0 && !on_box[i]) box_visible[i]<=1;
            end
            if(commit_now) begin
                pending_valid<=0; pending_effect<=`ITEM_NONE;
                if(pending_effect != `ITEM_TIME_BONUS && pending_effect != `ITEM_WALL_BREAKER) begin
                    active_effect <= (pending_duration != 0) ? pending_effect : `ITEM_NONE;
                    effect_seconds<=pending_duration; effect_subsecond<=0;
                end
            end
            if(phys_done && hit_valid && pickup_allowed) begin
                pickup_pulse<=1;
                pickup_index<=hit_index;
                pickup_effect<=rolled_effect;
                box_visible[hit_index]<=0; respawn_left[hit_index]<=RESPAWN_CYCLES;
                // Both paths keep the ordinary effect countdown above running:
                // neither blocking a debuff nor an instant bonus refreshes it.
                if(block_debuff) begin
                    debuff_blocked<=1;
                    pickup_effect<=`ITEM_NONE;
                end else if(DEFER_EFFECT) begin
                    pending_valid<=1; pending_effect<=rolled_effect;
                end else if(rolled_effect != `ITEM_TIME_BONUS && rolled_effect != `ITEM_WALL_BREAKER) begin
                    effect_subsecond<=0;
                    effect_seconds<=rolled_duration;
                    active_effect <= (rolled_duration != 0) ? rolled_effect : `ITEM_NONE;
                end
            end
        end
    end
endmodule
