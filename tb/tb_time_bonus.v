`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Independent integer-seconds model checks BCD arithmetic and terminal priority.
module tb_time_bonus;
    reg clk=0,rst=1,init=0,visible=0,action=0,bonus=0;
    reg [`GAME_STATE_W-1:0] state=`ST_PLAY;
    reg [3:0] stage=5;
    always #5 clk=~clk;
    wire [7:0] minutes[0:4],seconds[0:4];
    wire deadline[0:4];
    integer remaining[0:4],phase[0:4];
    reg started[0:4];
    function integer amount;input integer id;
        begin case(id)0:amount=10;1:amount=73;2:amount=0;3:amount=5999;default:amount=0;endcase end
    endfunction
    function [15:0] bcd;input integer total;integer m,s;
        begin m=total/60;s=total%60;bcd[15:12]=m/10;bcd[11:8]=m%10;bcd[7:4]=s/10;bcd[3:0]=s%10;end
    endfunction
    genvar g;
    generate for(g=0;g<5;g=g+1)begin: variants
        game_timer #(.CLK_HZ(g>=3 ? 1 : 4),.EASY_SECONDS(59),.HARD_SECONDS(5990),
            .HUGE_SECONDS(0),.BONUS_SECONDS(g==0 ? 10 : g==1 ? 73 : g==2 ? 0 : g==3 ? 6000 : -1)) timer_i (
            .clk(clk),.rst(rst),.phys_init(init),.maze_pixel_visible(visible),.player_action(action),
            .time_bonus_pulse(bonus),.game_state(state),.n_cells(stage),
            .elapsed_minutes_bcd(minutes[g]),.elapsed_seconds_bcd(seconds[g]),.time_up(deadline[g]));
    end endgenerate
    integer j,hz,next_time;reg tick,grant,expected_deadline;
    always @(posedge clk)begin
        for(j=0;j<5;j=j+1)begin
            hz=(j>=3)?1:4;
            grant=(state==`ST_PLAY && bonus && amount(j)>0);
            tick=(state==`ST_PLAY && started[j] && remaining[j]>0 && phase[j]==hz-1);
            expected_deadline=!rst && !init && !grant &&
                (remaining[j]==0 || (tick && remaining[j]==1));
            if(deadline[j] !== expected_deadline)begin
                $display("FAIL time bonus: deadline variant %0d remaining=%0d phase=%0d grant=%b",j,remaining[j],phase[j],grant);$fatal(1);
            end
            if(rst)begin remaining[j]=0;phase[j]=0;started[j]=0;end
            else if(init)begin remaining[j]=(stage==5)?59:(stage==15)?0:5990;phase[j]=0;started[j]=0;end
            else if(state==`ST_PLAY)begin
                next_time=remaining[j]-(tick?1:0)+(grant?amount(j):0);
                if(next_time>5999)next_time=5999;
                if(!started[j] || remaining[j]==0 || tick)phase[j]=0;
                else phase[j]=phase[j]+1;
                remaining[j]=next_time;
                if(visible && action)started[j]=1;
            end else begin phase[j]=0;started[j]=0;end
        end
        #1;
        for(j=0;j<5;j=j+1)if({minutes[j],seconds[j]} !== bcd(remaining[j]))begin
            $display("FAIL time bonus: variant %0d got=%02h:%02h expected=%0d",j,minutes[j],seconds[j],remaining[j]);$fatal(1);
        end
    end
    task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
    task load;input [3:0] n;begin stage=n;init=1;cycles(1);init=0;end endtask
    integer k;
    initial begin
        cycles(2);rst=0;load(5);
        // A bonus before first input preserves the unarmed state and phase.
        bonus=1;cycles(1);bonus=0;cycles(8);
        visible=1;action=1;cycles(1);visible=0;action=0;
        for(k=0;k<500;k=k+1)begin bonus=(k%19==0);cycles(1);end
        bonus=0;load(10);visible=1;action=1;cycles(1);action=0;visible=0;
        // Long runs cross every BCD borrow; repeated grants exercise saturation.
        for(k=0;k<26000;k=k+1)begin bonus=(k%797==0);cycles(1);end
        bonus=0;load(15);cycles(2);bonus=1;cycles(1);bonus=0;
        // Non-PLAY, phys_init and reset must ignore a concurrent grant.
        for(k=0;k<5;k=k+1)begin state=k;bonus=1;cycles(5);end
        state=`ST_PLAY;init=1;cycles(1);init=0;rst=1;cycles(1);rst=0;bonus=0;
        $display("PASS: time bonus independent seconds model, BCD carries/cap, tick priority, arming, empty timer, reset/state gating and parameter limits");
        $finish;
    end
    initial begin #1000000;$display("FAIL time bonus timeout");$fatal(1);end
endmodule
