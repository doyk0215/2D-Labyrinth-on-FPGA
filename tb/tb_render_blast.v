`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// render with BLAST_ENABLE: tiles inside the blast (filled square or ring, by
// Chebyshev distance from the centre tile) are the per-channel average of the
// normal wall or floor colour and the blast tint; every other tile is unchanged.
// The affine sample is forced to a tile centre, as in tb_render_palette.
module tb_render_blast;
    `include "brick_wall_model.vh"
    reg clk=0; always #5 clk=~clk;
    reg rst=1,frame_tick=0,data=1;
    reg blast_on=0,blast_fill=1;
    reg [1:0] blast_radius=2;
    reg [`COORD_W-1:0] bcol=6'd10,brow=6'd10;
    reg [11:0] brgb=12'hffe;
    wire [3:0] r,g,b;
    render #(.BLAST_ENABLE(1)) dut(.clk(clk),.rst(rst),.ce_pix(1'b0),.frame_tick(frame_tick),.game_state(`ST_PLAY),
        .time_min_bcd(8'd0),.time_sec_bcd(8'd0),.n_cells(5'd10),.cam_x(18'sd0),.cam_y(18'sd0),
        .angle(12'd0),.sin_q(16'sd0),.cos_q(16'sd16384),.pixel_x(10'd0),.pixel_y(10'd0),
        .active_video(1'b1),.hsync_in(1'b1),.vsync_in(1'b1),.maze_raddr(),.maze_rdata(data),
        .start_col(6'd19),.start_row(6'd19),.goal_col(6'd1),.goal_row(6'd1),
        .box_cols(48'd0),.box_rows(48'd0),.box_valid(8'd0),.box_visible(8'd0),
        .ball_on(1'b0),.fog_en(1'b0),.fog_clear(1'b1),
        .blast_on(blast_on),.blast_fill(blast_fill),.blast_radius(blast_radius),
        .blast_col(bcol),.blast_row(brow),.blast_rgb(brgb),
        .vga_r(r),.vga_g(g),.vga_b(b),.vga_hs(),.vga_vs(),.maze_pixel_visible(),.sin_snap(),.cos_snap());
    integer c,rw,dx,dy,d,hits,checked;
    reg [11:0] base,expected;
    reg hit;
    task fail;
        begin $display("FAIL render blast: tile=(%0d,%0d) on=%b fill=%b rad=%0d centre=(%0d,%0d) got=%h expected=%h",
            c,rw,blast_on,blast_fill,blast_radius,bcol,brow,{r,g,b},expected);$finish;end
    endtask
    function [11:0] mix;
        input [11:0] a,x;
        reg [4:0] sr,sg,sb;
        begin
            sr=a[11:8]+x[11:8];sg=a[7:4]+x[7:4];sb=a[3:0]+x[3:0];
            mix={sr[4:1],sg[4:1],sb[4:1]};
        end
    endfunction
    task frame;begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(5)@(negedge clk);end endtask
    // Every tile 2..20 in both directions (the start and goal markers are at
    // (19,19) and (1,1), so tiles 2..18 keep to plain walls or floor).
    task sweep;
        begin
            hits=0;
            for(rw=2;rw<=18;rw=rw+1)for(c=2;c<=18;c=c+1)begin
                force dut.walk_x_q=((c*16+8)<<<14);force dut.walk_y_q=((rw*16+8)<<<14);
                repeat(2)@(negedge clk);
                base=data ? brick_wall_model(c*16+8,rw*16+8) : 12'h346;
                dx=(c>bcol)?c-bcol:bcol-c;dy=(rw>brow)?rw-brow:brow-rw;d=(dx>dy)?dx:dy;
                hit=blast_on && (blast_fill ? (d<=blast_radius) : (d==blast_radius));
                expected=hit ? mix(base,brgb) : base;
                if(hit)hits=hits+1;
                if({r,g,b}!==expected)fail();
                checked=checked+1;
            end
        end endtask
    initial begin
        checked=0;
        repeat(3)@(negedge clk);rst=0;frame();
        // No blast: plain wall (data=1) and plain floor (data=0).
        blast_on=0;data=1;sweep();if(hits!=0)fail();
        data=0;sweep();
        // Flash: filled 5x5 over walls, then over floor.
        blast_on=1;blast_fill=1;blast_radius=2;brgb=12'hffe;data=1;sweep();if(hits!=25)begin $display("filled 5x5 hit %0d tiles",hits);fail();end
        data=0;sweep();
        // Rings: radius 1 has 8 tiles, radius 2 has 16.
        blast_fill=0;blast_radius=1;brgb=12'hf82;data=1;sweep();if(hits!=8)begin $display("ring 1 hit %0d tiles",hits);fail();end
        blast_radius=2;brgb=12'hf62;sweep();if(hits!=16)begin $display("ring 2 hit %0d tiles",hits);fail();end
        data=0;sweep();
        // Embers (filled) with another centre.
        bcol=6'd15;brow=6'd4;blast_fill=1;brgb=12'h520;data=1;sweep();
        // blast_on low again: back to normal.
        blast_on=0;sweep();if(hits!=0)fail();
        release dut.walk_x_q;release dut.walk_y_q;
        $display("PASS: render blast tint - filled 5x5 (25 tiles), ring 1 (8) and ring 2 (16) over wall and floor, other tiles unchanged, off = normal; %0d tiles checked",checked);
        $finish;
    end
    initial begin #50000000;$display("FAIL render blast: timeout");$finish;end
endmodule
