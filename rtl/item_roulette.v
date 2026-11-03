`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Runs in the system domain. display_frame/visual are acknowledged snapshots
// of the actual OLED frame, rather than an unsynchronised pixel-domain bus.
module item_roulette #(
    parameter integer CLK_HZ=100_000_000,
    parameter integer SPIN_MS=1500,
    parameter integer HOLD_MS=1000,
    parameter integer BLOCK_MS=1000
) (
    input wire clk,rst,phys_init,
    input wire [`GAME_STATE_W-1:0] game_state,
    input wire pickup_pulse,debuff_blocked,
    input wire [2:0] pickup_index,
    input wire [`ITEM_EFFECT_W-1:0] pickup_effect,
    input wire display_frame,
    input wire [3:0] display_visual,
    output wire busy,
    output wire [3:0] visual,
    output wire commit,
    output wire returning
);
    localparam [63:0] SPIN_RAW=64'd1*((CLK_HZ>0)?CLK_HZ:1)*((SPIN_MS>0)?SPIN_MS:0)/1000;
    localparam [63:0] HOLD_RAW=64'd1*((CLK_HZ>0)?CLK_HZ:1)*((HOLD_MS>0)?HOLD_MS:0)/1000;
    localparam [63:0] BLOCK_RAW=64'd1*((CLK_HZ>0)?CLK_HZ:1)*((BLOCK_MS>0)?BLOCK_MS:0)/1000;
    localparam [63:0] SPIN_CYCLES=(SPIN_RAW>0)?SPIN_RAW:1;
    localparam [63:0] HOLD_CYCLES=(HOLD_RAW>0)?HOLD_RAW:1;
    localparam [63:0] BLOCK_CYCLES=(BLOCK_RAW>0)?BLOCK_RAW:1;
    localparam [63:0] MAX_SH=(SPIN_CYCLES>HOLD_CYCLES)?SPIN_CYCLES:HOLD_CYCLES;
    localparam [63:0] MAX_CYCLES=(MAX_SH>BLOCK_CYCLES)?MAX_SH:BLOCK_CYCLES;
    localparam integer CW=(MAX_CYCLES>1)?$clog2(MAX_CYCLES+1):1;
    localparam [2:0] IDLE=0,SPIN=1,HOLD=2,BLOCK=3,RETURN=4;
    reg [2:0] state=IDLE;
    reg [2:0] icon=0,chosen=0;
    reg debuff_pool=0,shown=0,apply_pending=0;
    reg [CW-1:0] elapsed=0,step_elapsed=0;
    reg [63:0] step_interval;
    always @* begin
        if(elapsed<SPIN_CYCLES/4)step_interval=SPIN_CYCLES/64;
        else if(elapsed<SPIN_CYCLES/2)step_interval=SPIN_CYCLES/32;
        else if(elapsed<(SPIN_CYCLES*3)/4)step_interval=SPIN_CYCLES/16;
        else step_interval=SPIN_CYCLES/8;
        if(step_interval<1)step_interval=1;
    end
    wire enabled=!rst && !phys_init &&
                 (game_state==`ST_PLAY || game_state==`ST_PAUSED);
    wire running=enabled && game_state==`ST_PLAY;
    assign busy=enabled && state!=IDLE;
    assign visual={running && (state==SPIN || state==HOLD || state==BLOCK),icon};
    assign returning=running && state==RETURN;
    // CJX's playtest choice: activate when the stopped result is first visible,
    // then keep that icon on screen during HOLD while gameplay uses the effect.
    // item_ctrl and game_timer consume this same-edge grant together.
    assign commit=running && state==HOLD && !shown && apply_pending &&
                  display_frame && display_visual==visual;
    always @(posedge clk)begin
        if(!enabled)begin
            state<=IDLE;icon<=0;chosen<=0;debuff_pool<=0;shown<=0;apply_pending<=0;
            elapsed<=0;step_elapsed<=0;
        end else if(game_state==`ST_PAUSED)begin
            // Freeze the animation during pause; its OLED icon is hidden above.
        end else case(state)
            IDLE:begin
                shown<=0;elapsed<=0;step_elapsed<=0;apply_pending<=0;
                if(pickup_pulse)begin
                    if(debuff_blocked)begin state<=BLOCK;icon<=`ITEM_INVINCIBLE;end
                    else if(pickup_effect<=`ITEM_FOG)begin
                        state<=SPIN;chosen<=pickup_effect[2:0];debuff_pool<=pickup_effect>=4'd3;
                        icon<=(pickup_effect>=4'd3) ? 3'd3 : 3'd0;apply_pending<=1;
                    end
                end
            end
            SPIN:begin
                if(!shown)begin
                    if(display_frame && display_visual==visual)begin shown<=1;elapsed<=0;step_elapsed<=0;end
                end else if(elapsed==SPIN_CYCLES-1)begin
                    icon<=chosen;state<=HOLD;shown<=0;elapsed<=0;step_elapsed<=0;
                end else begin
                    elapsed<=elapsed+1'b1;
                    if(step_elapsed>=step_interval-1)begin
                        step_elapsed<=0;
                        if(debuff_pool)icon<=(icon==7)?3'd3:icon+1'b1;
                        else icon<=(icon==2)?3'd0:icon+1'b1;
                    end else step_elapsed<=step_elapsed+1'b1;
                end
            end
            HOLD,BLOCK:begin
                if(!shown)begin
                    if(display_frame && display_visual==visual)begin
                        shown<=1;elapsed<=0;
                        if(state==HOLD)apply_pending<=0;
                    end
                end else if((state==HOLD && elapsed==HOLD_CYCLES-1) ||
                            (state==BLOCK && elapsed==BLOCK_CYCLES-1))begin
                    state<=RETURN;shown<=0;elapsed<=0;
                end else elapsed<=elapsed+1'b1;
            end
            RETURN:if(display_frame && !display_visual[3])begin state<=IDLE;apply_pending<=0;end
            default:state<=IDLE;
        endcase
    end
endmodule
