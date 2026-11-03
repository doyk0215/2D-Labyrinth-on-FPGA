`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Game-flow controller for generation, play, pause, and result states.
// State values follow docs/parallel-workstreams.md. game_cfg is packed as
// {rot_speed_sel[1:0], restitution_sel[1:0], n_cells[3:0]} and is captured
// when a MENU start request is accepted at a frame boundary.
module game_ctrl #(
    parameter START_IN_MENU = 1'b0,
    parameter integer WIN_HOLD_FRAMES = 120,
    parameter integer LOSE_HOLD_FRAMES = 120
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       full_reset, // override legacy auto-start; always recover to MENU
    input  wire       frame_tick,
    input  wire       start_game,
    input  wire [7:0] game_cfg,
    input  wire       regen_button,
    input  wire       pause_button,
    input  wire       pause_resume,
    input  wire       pause_restart,
    input  wire       gen_busy,
    input  wire       gen_done,
    input  wire       in_goal,
    input  wire       time_up,
    output reg  [`GAME_STATE_W-1:0] game_state,
    output reg        gen_start,
    output reg        seed_capture,
    output reg        phys_init,
    output reg  [7:0] active_game_cfg,
    output wire       phys_en
);


    // GENERATE phases capture a fresh seed one cycle before maze_gen samples
    // gen_start, except normal in-game BTND regeneration, which reuses it.
    localparam [1:0] CAPTURE_SEED = 2'd0;
    localparam [1:0] START_GEN    = 2'd1;
    localparam [1:0] WAIT_GEN     = 2'd2;

    reg [1:0] gen_phase;
    reg       regen_pending;
    reg       reuse_seed_pending;
    reg       gen_done_pending;
    reg       start_pending;
    reg [7:0] start_cfg_pending;
    reg [15:0] win_frames_elapsed;
    localparam integer LOSE_COUNT_W = (LOSE_HOLD_FRAMES > 1) ? $clog2(LOSE_HOLD_FRAMES) : 1;
    reg [LOSE_COUNT_W-1:0] lose_frames_elapsed;

    assign phys_en = (game_state == `ST_PLAY);

    always @(posedge clk) begin
        if (rst || full_reset) begin
            if (full_reset) game_state <= `ST_MENU;
            else game_state <= START_IN_MENU ? `ST_MENU : `ST_GENERATE;
            gen_start       <= 1'b0;
            seed_capture    <= 1'b0;
            phys_init       <= 1'b0;
            gen_phase       <= CAPTURE_SEED;
            regen_pending   <= 1'b0;
            reuse_seed_pending <= 1'b0;
            gen_done_pending <= 1'b0;
            start_pending  <= 1'b0;
            start_cfg_pending <= {2'b00, 2'b00, 4'd5};
            active_game_cfg <= {2'b00, 2'b00, 4'd5};
            win_frames_elapsed <= 16'd0;
            lose_frames_elapsed <= {LOSE_COUNT_W{1'b0}};
        end else begin
            gen_start    <= 1'b0;
            seed_capture <= 1'b0;
            phys_init    <= 1'b0;

            // Hold a short button event until a frame boundary. The event is
            // accepted only in PLAY, so presses during GENERATE are ignored.
            if ((game_state == `ST_PLAY) && regen_button)
                regen_pending <= 1'b1;

            if ((game_state == `ST_GENERATE) && gen_done)
                gen_done_pending <= 1'b1;

            // A debounced confirm is only one system-clock cycle. Preserve
            // both the request and its configuration until frame_tick.
            if ((game_state == `ST_MENU) && start_game) begin
                start_pending <= 1'b1;
                start_cfg_pending <= game_cfg;
            end

            case (game_state)
                `ST_MENU: begin
                    if (frame_tick && (start_pending || start_game)) begin
                        game_state       <= `ST_GENERATE;
                        gen_phase        <= CAPTURE_SEED;
                        regen_pending    <= 1'b0;
                        reuse_seed_pending <= 1'b0;
                        gen_done_pending <= 1'b0;
                        active_game_cfg  <= start_pending ? start_cfg_pending : game_cfg;
                        start_pending    <= 1'b0;
                    end
                end

                `ST_GENERATE: begin
                    case (gen_phase)
                        CAPTURE_SEED: begin
                            if (!reuse_seed_pending)
                                seed_capture <= 1'b1;
                            reuse_seed_pending <= 1'b0;
                            gen_phase    <= START_GEN;
                        end

                        START_GEN: begin
                            gen_start <= 1'b1;
                            gen_phase <= WAIT_GEN;
                        end

                        default: begin
                            if (frame_tick &&
                                (gen_done_pending || gen_done) && !gen_busy) begin
                                game_state       <= `ST_PLAY;
                                gen_phase        <= CAPTURE_SEED;
                                gen_done_pending <= 1'b0;
                                phys_init        <= 1'b1;
                            end
                        end
                    endcase
                end

                `ST_PLAY: begin
                    if (frame_tick && time_up) begin
                        game_state <= `ST_LOSE;
                        lose_frames_elapsed <= {LOSE_COUNT_W{1'b0}};
                        regen_pending <= 1'b0;
                    end else if (frame_tick && in_goal) begin
                        game_state    <= `ST_WIN;
                        regen_pending <= 1'b0;
                        win_frames_elapsed <= 16'd0;
                    end else if (pause_button) begin
                        game_state <= `ST_PAUSED;
                        regen_pending <= 1'b0;
                    end else if (frame_tick) begin
                        if (regen_pending || regen_button) begin
                            game_state       <= `ST_GENERATE;
                            gen_phase        <= CAPTURE_SEED;
                            regen_pending    <= 1'b0;
                            reuse_seed_pending <= 1'b1;
                            gen_done_pending <= 1'b0;
                        end
                    end
                end

                `ST_PAUSED: begin
                    if (pause_resume) begin
                        game_state <= `ST_PLAY;
                    end else if (pause_restart) begin
                        game_state       <= `ST_GENERATE;
                        gen_phase        <= CAPTURE_SEED;
                        regen_pending    <= 1'b0;
                        reuse_seed_pending <= 1'b0;
                        gen_done_pending <= 1'b0;
                    end
                end

                `ST_WIN: begin
                    if (frame_tick) begin
                        if (win_frames_elapsed >= WIN_HOLD_FRAMES - 1) begin
                            game_state       <= `ST_GENERATE;
                            gen_phase        <= CAPTURE_SEED;
                            regen_pending    <= 1'b0;
                            reuse_seed_pending <= 1'b0;
                            gen_done_pending <= 1'b0;
                            win_frames_elapsed <= 16'd0;
                        end else begin
                            win_frames_elapsed <= win_frames_elapsed + 16'd1;
                        end
                    end
                end

                `ST_LOSE: begin
                    // Timeout returns to MENU without automatic regeneration.
                    if (frame_tick) begin
                        if ((LOSE_HOLD_FRAMES <= 1) ||
                            (lose_frames_elapsed >= LOSE_HOLD_FRAMES - 1)) begin
                            game_state <= `ST_MENU;
                            lose_frames_elapsed <= {LOSE_COUNT_W{1'b0}};
                            regen_pending <= 1'b0;
                            start_pending <= 1'b0;
                            gen_done_pending <= 1'b0;
                        end else begin
                            lose_frames_elapsed <= lose_frames_elapsed + 1'b1;
                        end
                    end
                end

                default: begin
                    game_state       <= `ST_GENERATE;
                    gen_phase        <= CAPTURE_SEED;
                    regen_pending    <= 1'b0;
                    reuse_seed_pending <= 1'b0;
                    gen_done_pending <= 1'b0;
                end
            endcase
        end
    end

endmodule
