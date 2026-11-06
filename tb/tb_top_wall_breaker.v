`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
// Real top: generated MEDIUM maze, a real physics pickup of a buff box that
// rolls WALL BREAKER, and the resulting edit of maze_ram. Only the ball
// position is placed (same method as the Story 9.5 top bench).
module tb_top_wall_breaker;
    reg clk=0,btnC=0,btnD=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    My_Top_Module #(.POR_CYCLES(4),.MENU_DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(64),
        .TIMER_CLK_HZ(256),.HARD_TIME_SECONDS(99),.ITEM_INVINCIBLE_SECONDS(30),
        .ITEM_RESPAWN_SECONDS(1),.ITEM_ROULETTE_ENABLE(1'b0)) dut (
        .clk(clk),.btnC(btnC),.btnU(1'b0),.btnD(btnD),.btnL(1'b0),.btnR(1'b0),
        .sw(16'h4000),.ps2_clk(ps2_clk),.ps2_data(ps2_data));
    integer breaks=0;
    always @(posedge clk)if(dut.wall_breaker_pulse)breaks=breaks+1;
    task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
    task fail;input [767:0] msg;
        begin $display("FAIL top wall breaker: %0s state=%0d effect=%0d",msg,dut.game_state,dut.item_effect);$finish;end endtask
    task frame;
        begin force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;cycles(80);end endtask
    task click;begin btnC=1;cycles(12);btnC=0;cycles(12);end endtask
    task start;integer guard;
        begin guard=0;
            while(!dut.menu_bg_visible && guard<400000)begin cycles(1);guard=guard+1;end
            if(!dut.menu_bg_visible)fail("menu backdrop did not finish");
            if(dut.menu_ctrl_i.selected_stage!==3'd1)begin btnD=1;cycles(12);btnD=0;cycles(12);end
            if(dut.menu_ctrl_i.selected_stage!==3'd1)fail("could not select MEDIUM");
            click();frame();guard=0;
            while(!dut.gen_done && guard<200000)begin cycles(1);guard=guard+1;end
            if(guard==200000)fail("generation timeout");frame();
            if(dut.game_state!==`ST_PLAY || dut.box_visible!==15)fail("PLAY/placed boxes");end endtask
    reg signed [17:0] x,y;
    task position;input integer slot;
        begin
            if(slot<0)begin x=(dut.start_col-dut.n_cells)*4096;y=(dut.start_row-dut.n_cells)*4096;end
            else begin x=(dut.box_cols[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;y=(dut.box_rows[slot*`COORD_W+:`COORD_W]-dut.n_cells)*4096;end
            force dut.ball_i.ball_x=x;force dut.ball_i.ball_y=y;
        end endtask
    // Wait for a seeded buff roll, then roll the ball onto the box.
    task pick;input integer slot;input integer desired;
        integer tries,guard;reg accepted;
        begin
            tries=0;accepted=0;
            while(!accepted && tries<200)begin
                position(-1);force dut.frame_tick=1;cycles(1);force dut.frame_tick=0;
                guard=0;while(!dut.phys_done && guard<100)begin cycles(1);guard=guard+1;end
                if(guard==100)fail("physics completion timeout");
                if(dut.item_i.buff_roll==desired)begin position(slot);accepted=1;end
                cycles(1);
                if(accepted && (!dut.item_pickup || dut.box_visible[slot]))fail("real physics did not consume box");
                cycles(2);tries=tries+1;
            end
            if(!accepted)fail("seeded physics samples never selected requested buff");
        end endtask

    reg before [0:`MAP_TILES-1];
    reg [7:0] boxes_valid_before, boxes_visible_before;
    reg [8*`COORD_W-1:0] box_cols_before, box_rows_before;
    integer i,c,r,bc,br,expected_changes,changed,prior_seconds;
    reg want_floor;
    initial begin
        force dut.frame_tick=0;force dut.oled_frame_begin=0;cycles(20);start();
        boxes_valid_before=dut.box_valid;
        box_cols_before=dut.box_cols;box_rows_before=dut.box_rows;
        boxes_visible_before=dut.box_visible;
        // Protection first: the breaker must leave a running effect alone.
        pick(0,`ITEM_INVINCIBLE);
        if(dut.item_effect!==`ITEM_INVINCIBLE)fail("invincibility did not start");
        prior_seconds=dut.item_seconds;
        for(i=0;i<`MAP_TILES;i=i+1)before[i]=dut.maze_ram_i.tile_mem[i];
        bc=dut.box_cols[1*`COORD_W+:`COORD_W];br=dut.box_rows[1*`COORD_W+:`COORD_W];
        breaks=0;
        pick(1,3);                       // buff_roll 3 is WALL BREAKER
        if(dut.item_pickup_effect!==`ITEM_WALL_BREAKER)fail("pickup was not WALL BREAKER");
        cycles(60);
        if(breaks!=1)fail("expected exactly one breaker pulse");
        if(dut.item_effect!==`ITEM_INVINCIBLE || dut.item_seconds>prior_seconds)fail("breaker ended or refreshed the running effect");
        // Every interior wall within 2 tiles of the box tile is floor; nothing else changed.
        changed=0;expected_changes=0;
        for(r=0;r<64;r=r+1)for(c=0;c<64;c=c+1)begin
            want_floor=(c>=1 && r>=1 && c<=2*dut.n_cells-1 && r<=2*dut.n_cells-1 &&
                        c>=bc-2 && c<=bc+2 && r>=br-2 && r<=br+2);
            if(before[r*64+c] && want_floor)expected_changes=expected_changes+1;
            if(dut.maze_ram_i.tile_mem[r*64+c]!==(want_floor ? 1'b0 : before[r*64+c]))begin
                $display("tile (%0d,%0d): was %b now %b, block centre (%0d,%0d)",c,r,before[r*64+c],dut.maze_ram_i.tile_mem[r*64+c],bc,br);
                fail("map differs from the expected blast");
            end
            if(before[r*64+c]!==dut.maze_ram_i.tile_mem[r*64+c])changed=changed+1;
        end
        if(expected_changes==0)fail("blast removed no walls, the check is vacuous");
        if(changed!=expected_changes)fail("changed tile count");
        if(dut.box_valid!==boxes_valid_before || dut.box_cols!==box_cols_before ||
           dut.box_rows!==box_rows_before)fail("blast changed the generated item boxes");
        if(dut.box_visible[3:2]!==boxes_visible_before[3:2] || dut.box_visible[1:0]!==2'b00)
            fail("blast hid uncollected boxes or restored collected boxes");
        frame();
        if(!dut.hud_i.wall_breaker_notice ||
           dut.hud_i.item_status_line!=={"WALL BREAKER",{8{8'h20}}})
            fail("VGA item row did not show WALL BREAKER");
        // The edit stays through ordinary frames.
        frame();frame();
        if(dut.maze_ram_i.tile_mem[(br+1)*64+bc]!==1'b0 && before[(br+1)*64+bc] && (br+1)<=2*dut.n_cells-1)
            fail("blast did not persist across frames");
        // BTND regenerates the same seeded maze, so the broken walls are back.
        btnD=1;cycles(12);btnD=0;cycles(12);frame();i=0;
        while(!dut.gen_done && i<200000)begin cycles(1);i=i+1;end
        if(i==200000)fail("regeneration timeout");
        frame();
        for(i=0;i<`MAP_TILES;i=i+1)if(dut.maze_ram_i.tile_mem[i]!==before[i])begin
            $display("tile index %0d differs after regeneration",i);fail("regeneration did not restore the map");end
        $display("PASS: top wall breaker - roulette-less real pickup, 5x5 blast in maze_ram (%0d walls opened), running effect untouched, map restored by regeneration",expected_changes);
        $finish;
    end
    initial begin #80000000;fail("timeout");end
endmodule
