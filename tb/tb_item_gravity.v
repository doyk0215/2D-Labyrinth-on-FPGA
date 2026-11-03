`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
module tb_item_gravity;
    reg clk=0,rst=1,frame_tick=0,init=0;
    always #5 clk=~clk;
    reg [3:0] effect=`ITEM_NONE;
    reg signed [15:0] sn=0,cs=16384;
    reg [1:0] restitution=0;
    wire signed [17:0] x,y;
    wire signed [11:0] vx,vy;
    wire done;
    wire [`MAP_ADDR_W-1:0] addr;
    reg wall=1;
    always@(posedge clk) wall <= addr[`MAP_ADDR_W-1:`COORD_W]==0 || addr[`MAP_ADDR_W-1:`COORD_W]>=30 || addr[`COORD_W-1:0]==0 || addr[`COORD_W-1:0]>=30;
    ball_physics dut (
        .clk(clk),.rst(rst),.frame_tick(frame_tick),.phys_init(init),.phys_en(1'b1),
        .spawn_col(6'd15),.spawn_row(6'd15),.goal_col(6'd1),.goal_row(6'd1),.n_cells(5'd15),
        .sin_q(sn),.cos_q(cs),.effect_code(effect),.restitution_sel(restitution),
        .maze_raddr(addr),.maze_rdata(wall),.ball_x(x),.ball_y(y),.vel_x(vx),.vel_y(vy),.phys_done(done),.in_goal()
    );
    task fail; input [767:0] msg;
        begin $display("FAIL item gravity: %0s x=%0d y=%0d vx=%0d vy=%0d",msg,x,y,vx,vy);$fatal(1);end endtask
    task cycles; input integer n; begin repeat(n)@(negedge clk);end endtask
    task fresh; begin init=1;cycles(1);init=0;cycles(2);end endtask
    task frame;
        input integer change_after_snapshot;
        integer guard;
        begin
            frame_tick=1;cycles(1);frame_tick=0;cycles(2);
            if(change_after_snapshot) effect=`ITEM_NONE;
            guard=0;while(!done && guard<60)begin cycles(1);guard=guard+1;end
            if(guard==60)fail("physics did not complete");cycles(2);
        end
    endtask
    task trig;
        input integer angle;
        real radians;
        begin radians=angle*3.141592653589793/180.0;
            sn=$rtoi($floor(16384.0*$sin(radians)+0.5));
            cs=$rtoi($floor(16384.0*$cos(radians)+0.5));end
    endtask
    integer angle,i,low,sel;
    reg signed [63:0] sum_x,sum_y,prod_x,prod_y;
    initial begin
        cycles(2);rst=0;
        // Integer model accumulates the entire Q product, including fractions.
        // Mixed low/normal steps test entering/leaving the effect mid-run.
        for(angle=0;angle<360;angle=angle+45)begin
            trig(angle);fresh();sum_x=0;sum_y=0;
            for(i=0;i<24;i=i+1)begin
                low=(i>=8 && i<16);effect=low ? `ITEM_LOW_GRAV : `ITEM_NONE;
                prod_x=$signed(sn)*`GRAVITY_Q14;prod_y=$signed(cs)*`GRAVITY_Q14;
                sum_x=sum_x+prod_x*(low ? 1 : 2);sum_y=sum_y+prod_y*(low ? 1 : 2);
                frame(low);
                if(vx !== (sum_x >>> (`GRAVITY_FRAC+1)) || vy !== (sum_y >>> (`GRAVITY_FRAC+1)))
                    fail("full signed product/fraction model or effect snapshot mismatch");
            end
        end
        // Accelerate to walls, including corners, for every restitution and
        // all octants. Low gravity keeps the existing cap and wall guarantees.
        for(sel=0;sel<4;sel=sel+1)begin
            restitution=sel;
            for(angle=0;angle<360;angle=angle+45)begin
                trig(angle);effect=`ITEM_LOW_GRAV;fresh();
                for(i=0;i<240;i=i+1)begin
                    frame(0);
                    if(x < -58112 || x > 58112 || y < -58112 || y > 58112)
                        fail("ball crossed a border wall with low gravity");
                    if(vx < -1280 || vx > 1280 || vy < -1280 || vy > 1280)
                        fail("velocity exceeded unchanged no-tunnelling cap");
                end
            end
        end
        $display("PASS: item low gravity complete-product/fraction model, effect snapshots/transitions, eight octants, all restitution walls and cap");
        $finish;
    end
    initial begin #10000000;fail("timeout");end
endmodule
