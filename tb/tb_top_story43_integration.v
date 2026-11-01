`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

module tb_top_story43_integration;

    reg clk = 1'b0;
    reg btnC = 1'b0;
    reg btnU = 1'b0;
    reg btnL = 1'b0;
    reg btnR = 1'b0;
    reg btnD = 1'b0;
    wire [15:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs;
    tri1 ps2_clk, ps2_data;
    wire oled_cs, oled_mosi, oled_sclk, oled_dc, oled_res, oled_vbatc, oled_vddc;
    integer errors = 0;
    integer timeout;
    integer i;
    integer gen_start_count = 0;
    reg [511:0] old_text;
    reg [11:0] angle_before_settings;

    always #5 clk = ~clk;

    My_Top_Module #(
        .SNAP_DEBOUNCE_CYCLES(3), .MENU_DEBOUNCE_CYCLES(3), .POR_CYCLES(4)
    ) dut (
        .clk(clk), .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR),
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
    end

    task press_button;
        input [2:0] button_id;
        begin
            @(negedge clk);
            case (button_id)
                3'd0: btnL = 1'b1;
                3'd1: btnU = 1'b1;
                3'd2: btnC = 1'b1;
                3'd3: btnD = 1'b1;
                3'd4: btnR = 1'b1;
                default: begin end
            endcase
            repeat (12) @(negedge clk);
            case (button_id)
                3'd0: btnL = 1'b0;
                3'd1: btnU = 1'b0;
                3'd2: btnC = 1'b0;
                3'd3: btnD = 1'b0;
                3'd4: btnR = 1'b0;
                default: begin end
            endcase
            repeat (12) @(negedge clk);
        end
    endtask

    task wait_state;
        input [`GAME_STATE_W-1:0] expected;
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

    task check_oled_update;
        input [2:0] button_id;
        begin
            force dut.oled_frame_begin = 1'b0;
            old_text = dut.text_active;
            press_button(button_id);
            if (old_text === dut.status_text) begin
                $display("FAIL: menu action did not change OLED text");
                errors = errors + 1;
            end
            timeout = 0;
            while (((dut.text_mailbox !== dut.status_text) ||
                    (dut.text_req_toggle != dut.text_ack_sync[1]) ||
                    !dut.text_pending_valid) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!dut.text_pending_valid) begin
                $display("FAIL: changed menu text did not reach OLED pending snapshot");
                errors = errors + 1;
            end else begin
                repeat (20) @(posedge clk);
                #1;
                if (dut.text_active !== old_text) begin
                    $display("FAIL: OLED text changed before frame_begin");
                    errors = errors + 1;
                end
                force dut.oled_frame_begin = 1'b1;
                repeat (20) @(posedge clk);
                release dut.oled_frame_begin;
                #1;
                if (dut.text_active !== dut.status_text) begin
                    $display("FAIL: OLED frame snapshot missed the latest menu text");
                    errors = errors + 1;
                end
            end
            release dut.oled_frame_begin;
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b1;
        repeat (12) @(posedge clk);
        #1;
        if (dut.game_state !== `ST_MENU || dut.game_cfg !== 8'h05 ||
            dut.gen_start !== 1'b0 || gen_start_count != 0) begin
            $display("FAIL: startup was not in stage-selection MENU");
            errors = errors + 1;
        end

        press_button(3'd3); // choose HARD
        if (dut.game_cfg !== 8'h1A) begin
            $display("FAIL: stage selection did not retain HARD configuration");
            errors = errors + 1;
        end

        angle_before_settings = dut.angle;
        check_oled_update(3'd0); // BTNL opens settings page
        if (!dut.menu_ctrl_i.settings_page || dut.game_cfg !== 8'h1A ||
            dut.game_state !== `ST_MENU || gen_start_count != 0 ||
            dut.angle !== angle_before_settings) begin
            $display("FAIL: BTNL did not open settings without starting a game");
            errors = errors + 1;
        end

        check_oled_update(3'd1); // BTNU: NORMAL -> FAST
        if (dut.game_cfg !== 8'h9A || !dut.menu_ctrl_i.settings_page) begin
            $display("FAIL: settings speed did not reach game_cfg or OLED frame");
            errors = errors + 1;
        end

        press_button(3'd2); // BTNC returns to the stage page
        if (dut.menu_ctrl_i.settings_page || dut.start_game ||
            dut.game_cfg !== 8'h9A || dut.menu_ctrl_i.selected_stage !== 1'b1) begin
            $display("FAIL: BTNC in settings did not return while keeping choices");
            errors = errors + 1;
        end

        press_button(3'd2); // BTNC on stage page starts
        wait_state(`ST_GENERATE);
        if (dut.active_game_cfg !== 8'h9A ||
            dut.angle_i.rot_speed_sel !== 2'b10) begin
            $display("FAIL: selected FAST configuration was not latched for the game");
            errors = errors + 1;
        end
        wait_state(`ST_PLAY);
        if (gen_start_count != 1) begin
            $display("FAIL: expected one maze generation, got %0d", gen_start_count);
            errors = errors + 1;
        end

        // A later menu value cannot retune the already-running game.
        force dut.game_cfg = 8'h5A;
        #1;
        if (dut.active_game_cfg !== 8'h9A || dut.angle_i.rot_speed_sel !== 2'b10) begin
            $display("FAIL: a later game_cfg change retuned the active game");
            errors = errors + 1;
        end
        release dut.game_cfg;

        // FAST is 1536 angle counts per 60 frame ticks; the board-button
        // rotation path must use the captured setting.
        @(negedge clk); btnR = 1'b1;
        timeout = 0;
        while (dut.rot_cmd !== 2'sd1 && timeout < 20) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (dut.rot_cmd !== 2'sd1) begin
            $display("FAIL: BTNR did not produce a clockwise command");
            errors = errors + 1;
        end
        for (i = 0; i < 60; i = i + 1) @(posedge clk);
        #1;
        if (dut.angle !== 12'd1536) begin
            $display("FAIL: top-level FAST rate expected angle 1536, got %0d", dut.angle);
            errors = errors + 1;
        end
        @(negedge clk); btnR = 1'b0;

        // Reset from PLAY returns to MENU, clears the stage but retains FAST.
        press_button(3'd2);
        wait_state(`ST_MENU);
        if (dut.game_cfg !== 8'h85 || dut.menu_ctrl_i.settings_page ||
            dut.menu_ctrl_i.selected_stage !== 1'b0) begin
            $display("FAIL: game reset did not preserve speed and reset the stage page");
            errors = errors + 1;
        end
        release dut.frame_tick;

        if (errors == 0)
            $display("PASS: Story 4.3 top settings, OLED snapshots, next-game rate latch, and FAST rotation");
        else
            $display("FAIL: Story 4.3 integration had %0d errors", errors);
        $finish;
    end
endmodule
