`timescale 1ns / 1ps

module tb_top_story44_integration;
    localparam [1:0] MENU = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY = 2'b10;
    localparam [1:0] WIN = 2'b11;
    localparam integer TIMER_CLK_HZ = 100_000;

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
    integer gen_start_count = 0;
    reg [511:0] old_active_text;

    always #5 clk = ~clk;

    My_Top_Module #(
        .SNAP_DEBOUNCE_CYCLES(2), .MENU_DEBOUNCE_CYCLES(2), .POR_CYCLES(2),
        .WIN_HOLD_FRAMES(2), .TIMER_CLK_HZ(TIMER_CLK_HZ)
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

    task pulse_frame;
        begin
            @(negedge clk); force dut.frame_tick = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); force dut.frame_tick = 1'b0;
        end
    endtask

    task press_confirm;
        begin
            @(negedge clk); btnC = 1'b1;
            repeat (12) @(negedge clk);
            btnC = 1'b0;
            repeat (12) @(negedge clk);
        end
    endtask

    task wait_state;
        input [1:0] expected;
        begin
            timeout = 0;
            while ((dut.game_state !== expected) && (timeout < 200000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (dut.game_state !== expected) begin
                $display("FAIL Story 4.4 integration: timeout waiting for state %b, got %b",
                         expected, dut.game_state);
                errors = errors + 1;
            end
        end
    endtask

    task wait_generation_done;
        begin
            timeout = 0;
            while ((dut.gen_done !== 1'b1) && (timeout < 200000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (dut.gen_done !== 1'b1) begin
                $display("FAIL Story 4.4 integration: timed out waiting for gen_done");
                errors = errors + 1;
            end
            pulse_frame;
            wait_state(PLAY);
        end
    endtask

    task wait_text_pending;
        begin
            timeout = 0;
            while (((dut.text_mailbox !== dut.status_text) ||
                    (dut.text_req_toggle != dut.text_ack_sync[1]) ||
                    !dut.text_pending_valid ||
                    (dut.text_pending !== dut.status_text)) && (timeout < 2000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!dut.text_pending_valid || dut.text_mailbox !== dut.status_text) begin
                $display("FAIL Story 4.4 integration: new status text did not reach OLED pending buffer");
                errors = errors + 1;
            end
        end
    endtask

    task apply_status_at_frame;
        begin
            force dut.oled_frame_begin = 1'b0;
            wait_text_pending;
            old_active_text = dut.text_active;
            repeat (12) @(posedge dut.clk_6m25);
            #1;
            if (dut.text_active !== old_active_text) begin
                $display("FAIL Story 4.4 integration: status changed before OLED frame boundary");
                errors = errors + 1;
            end
            force dut.oled_frame_begin = 1'b1;
            repeat (4) @(posedge dut.clk_6m25);
            #1;
            release dut.oled_frame_begin;
            if (dut.text_active !== dut.status_text) begin
                $display("FAIL Story 4.4 integration: OLED did not take the complete status snapshot");
                errors = errors + 1;
            end
        end
    endtask

    task expect_char;
        input integer byte_index;
        input [7:0] expected;
        input [255:0] label_text;
        reg [7:0] actual;
        begin
            actual = dut.status_text[8 * byte_index +: 8];
            if (actual !== expected) begin
                $display("FAIL Story 4.4 integration %0s at byte %0d: got '%c', expected '%c'",
                         label_text, byte_index, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        force dut.frame_tick = 1'b0;
        force dut.oled_frame_begin = 1'b0;
        repeat (12) @(posedge clk);
        #1;
        if (dut.game_state !== MENU) begin
            $display("FAIL Story 4.4 integration: power-on did not show MENU");
            errors = errors + 1;
        end
        expect_char(0, "S", "stage-menu text retained");

        press_confirm;
        pulse_frame;
        wait_state(GENERATE);
        if (dut.active_game_cfg !== 8'h05) begin
            $display("FAIL Story 4.4 integration: EASY stage not captured at start");
            errors = errors + 1;
        end
        wait_generation_done;
        if (gen_start_count != 1 || dut.elapsed_minutes_bcd !== 8'h00 ||
            dut.elapsed_seconds_bcd !== 8'h00) begin
            $display("FAIL Story 4.4 integration: first PLAY did not start stage one at 00:00");
            errors = errors + 1;
        end
        expect_char(6, "1", "stage one from active configuration");
        expect_char(21, "0", "timer displayed from zero");

        // Synchronize the initial PLAY status into the OLED, then hold its
        // frame snapshot while the first elapsed second changes the text.
        force dut.oled_frame_begin = 1'b0;
        wait_text_pending;
        force dut.oled_frame_begin = 1'b1;
        repeat (4) @(posedge dut.clk_6m25);
        #1 force dut.oled_frame_begin = 1'b0;
        old_active_text = dut.text_active;

        // phys_init clears the timer on the first PLAY edge; start a fresh
        // one-second interval after that clear pulse has passed.
        @(negedge clk);
        while (dut.phys_init) @(negedge clk);
        timeout = 0;
        while ((dut.elapsed_seconds_bcd == 8'h00) &&
               (timeout < TIMER_CLK_HZ + 10)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        #1;
        if (dut.elapsed_seconds_bcd !== 8'h01) begin
            $display("FAIL Story 4.4 integration: one-second count did not reach 00:01");
            errors = errors + 1;
        end
        expect_char(25, "1", "live elapsed seconds");
        force dut.oled_frame_begin = 1'b0;
        wait_text_pending;
        if (dut.text_active !== old_active_text) begin
            $display("FAIL Story 4.4 integration: live timer tore the active OLED frame");
            errors = errors + 1;
        end
        force dut.oled_frame_begin = 1'b1;
        repeat (4) @(posedge dut.clk_6m25);
        #1 release dut.oled_frame_begin;
        if (dut.text_active !== dut.status_text) begin
            $display("FAIL Story 4.4 integration: complete live timer page missed OLED frame latch");
            errors = errors + 1;
        end

        force dut.in_goal = 1'b1;
        pulse_frame;
        release dut.in_goal;
        wait_state(WIN);
        if (dut.status_text[8*32 +: 8] !== "Y") begin
            $display("FAIL Story 4.4 integration: OLED did not display retained WIN status");
            errors = errors + 1;
        end
        repeat (TIMER_CLK_HZ * 3) @(posedge clk);
        #1;
        if (dut.elapsed_seconds_bcd !== 8'h01 || dut.elapsed_minutes_bcd !== 8'h00) begin
            $display("FAIL Story 4.4 integration: elapsed timer advanced during WIN");
            errors = errors + 1;
        end

        pulse_frame;
        pulse_frame;
        wait_state(GENERATE);
        wait_generation_done;
        @(posedge clk); #1;
        if (gen_start_count != 2 || dut.elapsed_minutes_bcd !== 8'h00 ||
            dut.elapsed_seconds_bcd !== 8'h00) begin
            $display("FAIL Story 4.4 integration: automatic replay did not clear the old maze time");
            errors = errors + 1;
        end

        press_confirm;
        wait_state(MENU);
        if (dut.elapsed_minutes_bcd !== 8'h00 || dut.elapsed_seconds_bcd !== 8'h00 ||
            dut.status_text[7:0] !== "S") begin
            $display("FAIL Story 4.4 integration: reset did not clear time and restore menu text");
            errors = errors + 1;
        end
        release dut.frame_tick;

        if (errors == 0)
            $display("PASS: Story 4.4 top status, timer, WIN freeze, replay clear, reset, and OLED frame snapshot");
        else
            $display("FAIL: Story 4.4 integration had %0d errors", errors);
        $finish;
    end
endmodule
