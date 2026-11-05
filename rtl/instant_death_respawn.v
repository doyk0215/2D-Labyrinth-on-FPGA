`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Queue the acknowledged instant item until blanking. Apply one clock after
// frame_tick, allowing game_ctrl's terminal/regenerate decision to win first.
// Pause retains the request; new maze/reset/menu/results cancel it.
module instant_death_respawn (
    input wire clk,rst,phys_init,frame_tick,request,
    input wire [`GAME_STATE_W-1:0] game_state,
    input wire pause_requested,time_up,in_goal,
    output wire apply,
    output wire discard_step
);
    reg pending=0,frame_window=0;
    // This mask must depend only on registered queue/window state. Using
    // apply to gate item phys_done would feed the instant time-bonus path
    // through time_up back into apply when roulette is disabled.
    assign discard_step=pending && frame_window;
    assign apply=discard_step && game_state==`ST_PLAY &&
                 !rst && !phys_init && !pause_requested && !time_up && !in_goal;
    always @(posedge clk) begin
        if(rst || phys_init || (game_state!=`ST_PLAY && game_state!=`ST_PAUSED)) begin
            pending<=0;frame_window<=0;
        end else begin
            frame_window<=game_state==`ST_PLAY && frame_tick;
            if(request)pending<=1;
            else if(apply)pending<=0;
        end
    end
endmodule
