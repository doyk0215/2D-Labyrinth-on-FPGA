`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_render_palette;
    `include "brick_wall_model.vh"
    reg clk=0; always #5 clk=~clk;
    reg rst=1,frame_tick=0,data=1;
    reg [2:0] state=`ST_PLAY;
    wire [3:0] r,g,b;
    render dut(.clk(clk),.rst(rst),.ce_pix(1'b0),.frame_tick(frame_tick),.game_state(state),
        .time_min_bcd(8'd0),.time_sec_bcd(8'd0),.n_cells(5'd10),.cam_x(18'sd0),.cam_y(18'sd0),
        .angle(12'd0),.sin_q(16'sd0),.cos_q(16'sd16384),.pixel_x(10'd0),.pixel_y(10'd0),
        .active_video(1'b1),.hsync_in(1'b1),.vsync_in(1'b1),.maze_raddr(),.maze_rdata(data),
        .start_col(6'd19),.start_row(6'd19),.goal_col(6'd1),.goal_row(6'd1),
        .box_cols(48'd0),.box_rows(48'd0),.box_valid(8'd0),.box_visible(8'd0),
        .ball_on(1'b0),.fog_en(1'b0),.fog_clear(1'b1),.vga_r(r),.vga_g(g),.vga_b(b),
        .vga_hs(),.vga_vs(),.maze_pixel_visible(),.sin_snap(),.cos_snap());
    integer xx,yy,s;
    reg [11:0] expected;
    task fail;
        begin $display("FAIL palette: state=%0d pixel=(%0d,%0d) got=%h expected=%h",state,xx,yy,{r,g,b},expected);$finish;end
    endtask
    function [11:0] gray;
        input [11:0] warm;
        case(warm)
            12'h987:gray=12'h777;12'ha98:gray=12'h888;12'h998:gray=12'h778;12'h887:gray=12'h667;
            12'h433:gray=12'h222;12'h654:gray=12'h444;12'hba8:gray=12'haaa;default:gray=12'h555;
        endcase
    endfunction
    task frame;
        begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(5)@(negedge clk);end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        // Force only the affine sample, keeping the production state/palette
        // snapshot and one-clock output pipeline active.
        force dut.walk_x_q=27'sd524288; force dut.walk_y_q=27'sd524288;
        frame();
        for(s=0;s<6;s=s+1) begin
            state=s;frame();
            for(yy=32;yy<96;yy=yy+1) for(xx=32;xx<96;xx=xx+1) begin
                force dut.walk_x_q=xx<<<14;force dut.walk_y_q=yy<<<14;
                repeat(2)@(negedge clk);
                expected=brick_wall_model(xx,yy);if(s!=`ST_PLAY) expected=gray(expected);
                if({r,g,b}!==expected) fail();
            end
        end
        force dut.walk_x_q=27'sd1556480;force dut.walk_y_q=27'sd1556480; // (95,95)
        state=`ST_PLAY;frame();expected=brick_wall_model(95,95);
        state=`ST_PAUSED;repeat(4)@(negedge clk);
        if({r,g,b}!==expected) fail(); // palette cannot switch mid-frame
        frame();expected=gray(expected);if({r,g,b}!==expected) fail();
        state=`ST_PLAY;frame();expected=brick_wall_model(95,95);if({r,g,b}!==expected) fail();
        data=0;state=`ST_MENU;frame();expected=12'h222;if({r,g,b}!==expected) fail();
        state=`ST_PLAY;frame();expected=12'h346;if({r,g,b}!==expected) fail();
        release dut.walk_x_q;release dut.walk_y_q;
        $display("PASS: gray walls outside PLAY, beige in PLAY, frozen mid-frame, resume, menu floor and existing PLAY floor");
        $finish;
    end
endmodule
