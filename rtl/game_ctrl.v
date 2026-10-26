`timescale 1ns / 1ps

// Game-flow controller for Story 1.4.
// State values follow docs/parallel-workstreams.md. MENU is kept ready for
// Epic 4; the current build starts directly in GENERATE after reset.
module game_ctrl #(
    parameter START_IN_MENU = 1'b0
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       start_game,
    input  wire       regen_button,
    input  wire       gen_busy,
    input  wire       gen_done,
    input  wire       in_goal,
    output reg  [1:0] game_state,
    output reg        gen_start,
    output reg        seed_capture,
    output reg        phys_init,
    output wire       phys_en
);

    localparam [1:0] MENU     = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY     = 2'b10;
    localparam [1:0] WIN      = 2'b11;

    // GENERATE phases ensure the seed source captures its value one cycle
    // before maze_gen samples gen_start.
    localparam [1:0] CAPTURE_SEED = 2'd0;
    localparam [1:0] START_GEN    = 2'd1;
    localparam [1:0] WAIT_GEN     = 2'd2;

    reg [1:0] gen_phase;
    reg       regen_pending;
    reg       gen_done_pending;

    assign phys_en = (game_state == PLAY);

    always @(posedge clk) begin
        if (rst) begin
            game_state      <= START_IN_MENU ? MENU : GENERATE;
            gen_start       <= 1'b0;
            seed_capture    <= 1'b0;
            phys_init       <= 1'b0;
            gen_phase       <= CAPTURE_SEED;
            regen_pending   <= 1'b0;
            gen_done_pending <= 1'b0;
        end else begin
            gen_start    <= 1'b0;
            seed_capture <= 1'b0;
            phys_init    <= 1'b0;

            // Hold a short button event until a frame boundary. The event is
            // accepted only in PLAY, so presses during GENERATE are ignored.
            if ((game_state == PLAY) && regen_button)
                regen_pending <= 1'b1;

            if ((game_state == GENERATE) && gen_done)
                gen_done_pending <= 1'b1;

            case (game_state)
                MENU: begin
                    if (frame_tick && start_game) begin
                        game_state       <= GENERATE;
                        gen_phase        <= CAPTURE_SEED;
                        regen_pending    <= 1'b0;
                        gen_done_pending <= 1'b0;
                    end
                end

                GENERATE: begin
                    case (gen_phase)
                        CAPTURE_SEED: begin
                            seed_capture <= 1'b1;
                            gen_phase    <= START_GEN;
                        end

                        START_GEN: begin
                            gen_start <= 1'b1;
                            gen_phase <= WAIT_GEN;
                        end

                        default: begin
                            if (frame_tick &&
                                (gen_done_pending || gen_done) && !gen_busy) begin
                                game_state       <= PLAY;
                                gen_phase        <= CAPTURE_SEED;
                                gen_done_pending <= 1'b0;
                                phys_init        <= 1'b1;
                            end
                        end
                    endcase
                end

                PLAY: begin
                    if (frame_tick) begin
                        if (in_goal) begin
                            game_state    <= WIN;
                            regen_pending <= 1'b0;
                        end else if (regen_pending || regen_button) begin
                            game_state       <= GENERATE;
                            gen_phase        <= CAPTURE_SEED;
                            regen_pending    <= 1'b0;
                            gen_done_pending <= 1'b0;
                        end
                    end
                end

                WIN: begin
                    if (frame_tick) begin
                        game_state       <= GENERATE;
                        gen_phase        <= CAPTURE_SEED;
                        regen_pending    <= 1'b0;
                        gen_done_pending <= 1'b0;
                    end
                end

                default: begin
                    game_state       <= GENERATE;
                    gen_phase        <= CAPTURE_SEED;
                    regen_pending    <= 1'b0;
                    gen_done_pending <= 1'b0;
                end
            endcase
        end
    end

endmodule
