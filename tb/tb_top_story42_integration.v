`timescale 1ns / 1ps

module tb_top_story42_integration;
    localparam [1:0] MENU = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY = 2'b10;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    reg btnU = 1'b0;
    reg btnD = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;
    integer gen_start_count = 0;
    integer errors = 0;
    integer timeout;

    always #5 clk = ~clk;

    My_Top_Module #(.POR_CYCLES(4), .MENU_DEBOUNCE_CYCLES(3)) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnL(1'b0), .btnR(1'b0),
        .btnD(btnD), .sw(16'h0001), .led(led),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .oled_cs(oled_cs), .oled_mosi(oled_mosi), .oled_sclk(oled_sclk),
        .oled_dc(oled_dc), .oled_res(oled_res),
        .oled_vbatc(oled_vbatc), .oled_vddc(oled_vddc)
    );

    always @(posedge clk) begin
        if (dut.gen_start)
            gen_start_count = gen_start_count + 1;
        if ((dut.game_state == MENU) && dut.active_video_d &&
            {vga_r, vga_g, vga_b} !== 12'h002) begin
            $display("FAIL: menu pixels leaked into VGA output");
            errors = errors + 1;
        end
    end

    task press_button;
        input [1:0] button_id;
        begin
            @(negedge clk);
            case (button_id)
                2'd1: btnU = 1'b1;
                2'd2: btnC = 1'b1;
                2'd3: btnD = 1'b1;
                default: begin end
            endcase
            repeat (12) @(negedge clk);
            case (button_id)
                2'd1: btnU = 1'b0;
                2'd2: btnC = 1'b0;
                2'd3: btnD = 1'b0;
                default: begin end
            endcase
            repeat (12) @(negedge clk);
        end
    endtask

    task wait_state;
        input [1:0] expected;
        begin
            timeout = 0;
            while ((dut.game_state !== expected) && (timeout < 20000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (dut.game_state !== expected) begin
                $display("FAIL: timeout waiting for state %b, got %b", expected, dut.game_state);
                errors = errors + 1;
            end
        end
    endtask

    task apply_oled_text_snapshot;
        begin
            timeout = 0;
            while (((dut.text_mailbox !== dut.status_text) ||
                    (dut.text_req_toggle != dut.text_ack_sync[1]) ||
                    !dut.text_pending_valid) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!dut.text_pending_valid) begin
                $display("FAIL: menu text did not reach OLED pending snapshot");
                errors = errors + 1;
            end else begin
                force dut.oled_frame_begin = 1'b1;
                repeat (20) @(posedge clk);
                release dut.oled_frame_begin;
                #1;
                if (dut.text_active !== dut.status_text) begin
                    $display("FAIL: OLED frame snapshot does not match selected menu text");
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b1;
        repeat (12) @(posedge clk);
        #1;
        if (dut.game_state !== MENU || dut.game_cfg !== 8'h05 ||
            dut.gen_start !== 1'b0 || gen_start_count != 0) begin
            $display("FAIL: startup did not remain in MENU awaiting confirmation");
            errors = errors + 1;
        end

        repeat (30) @(posedge clk);
        if (dut.game_state !== MENU || gen_start_count != 0) begin
            $display("FAIL: game generated before stage confirmation");
            errors = errors + 1;
        end

        // Exercise DOWN and UP navigation, then confirm the smaller EASY maze.
        press_button(2'd3);
        if (dut.game_cfg !== 8'h1A || dut.menu_ctrl_i.selected_stage !== 1'b1) begin
            $display("FAIL: BTND did not select HARD stage");
            errors = errors + 1;
        end
        apply_oled_text_snapshot();
        press_button(2'd1);
        if (dut.game_cfg !== 8'h05 || dut.menu_ctrl_i.selected_stage !== 1'b0) begin
            $display("FAIL: BTNU did not return to EASY stage");
            errors = errors + 1;
        end
        apply_oled_text_snapshot();
        if (gen_start_count != 0) begin
            $display("FAIL: stage navigation started maze generation");
            errors = errors + 1;
        end

        press_button(2'd2);
        wait_state(GENERATE);
        if (dut.active_game_cfg !== 8'h05) begin
            $display("FAIL: game controller did not capture selected EASY configuration");
            errors = errors + 1;
        end
        timeout = 0;
        while ((gen_start_count == 0) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (gen_start_count != 1 || dut.gen_i.n !== 4'd5) begin
            $display("FAIL: maze generator did not receive selected N=5");
            errors = errors + 1;
        end
        if (dut.maze_ram_i.ren_r !== 1'b0 || dut.render_enable_d !== 1'b0) begin
            $display("FAIL: renderer was enabled before maze generation completed");
            errors = errors + 1;
        end

        wait_state(PLAY);
        if (dut.start_col !== 5'd6 || dut.goal_col !== 5'd14 ||
            dut.start_row !== 5'd6 || dut.goal_row !== 5'd14) begin
            $display("FAIL: N=5 maze was not centred in the tile map");
            errors = errors + 1;
        end

        // The same debounced center button returns active play to the menu.
        press_button(2'd2);
        wait_state(MENU);
        if (dut.menu_ctrl_i.selected_stage !== 1'b0 || dut.game_cfg !== 8'h05) begin
            $display("FAIL: BTNC reset did not restore the initial menu selection");
            errors = errors + 1;
        end
        if (gen_start_count != 1) begin
            $display("FAIL: unexpected generation count %0d", gen_start_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: Story 4.2 top menu, frame handoff, N=5 maze, reset, OLED text snapshot");
        else
            $display("FAIL: Story 4.2 integration had %0d errors", errors);
        release dut.frame_tick;
        $finish;
    end
endmodule
