`timescale 1ns / 1ps

// Story 4.2 stage selector. The display buffer stores ASCII bytes in
// status_text[8*k +: 8], with k = row*16 + column (top-left is byte 0).
// game_cfg is {rot_speed_sel[1:0], restitution_sel[1:0], n_cells[3:0]}.
//
// Stage table (kept here as the single source of truth):
//   0 EASY: N=5 cells, restitution_sel=0, rot_speed_sel=0
//   1 HARD: N=10 cells, restitution_sel=1, rot_speed_sel=0
module menu_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        menu_active,
    input  wire        btn_up,
    input  wire        btn_down,
    input  wire        btn_confirm,
    output reg         start_game,
    output reg  [7:0]  game_cfg,
    output reg  [511:0] status_text,
    output reg         selected_stage
);

    function [511:0] pack_text;
        input [127:0] r0;
        input [127:0] r1;
        input [127:0] r2;
        input [127:0] r3;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                pack_text[8 * i        +: 8] = r0[127 - 8 * i -: 8];
                pack_text[8 * (16 + i) +: 8] = r1[127 - 8 * i -: 8];
                pack_text[8 * (32 + i) +: 8] = r2[127 - 8 * i -: 8];
                pack_text[8 * (48 + i) +: 8] = r3[127 - 8 * i -: 8];
            end
        end
    endfunction

    always @* begin
        case (selected_stage)
            1'b0: begin
                game_cfg = {2'b00, 2'b00, 4'd5};
                status_text = pack_text("SELECT A STAGE  ",
                                        ">EASY N=05 R=00 ",
                                        " HARD N=10 R=01 ",
                                        "UP/DN MOVE C GO ");
            end
            default: begin
                game_cfg = {2'b00, 2'b01, 4'd10};
                status_text = pack_text("SELECT A STAGE  ",
                                        " EASY N=05 R=00 ",
                                        ">HARD N=10 R=01 ",
                                        "UP/DN MOVE C GO ");
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            selected_stage <= 1'b0;
            start_game <= 1'b0;
        end else begin
            start_game <= 1'b0;
            if (menu_active) begin
                if (btn_up || btn_down)
                    selected_stage <= ~selected_stage;
                if (btn_confirm)
                    start_game <= 1'b1;
            end
        end
    end

endmodule
