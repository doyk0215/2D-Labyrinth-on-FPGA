`timescale 1ns / 1ps

module tb_game_ctrl;
    localparam [1:0] MENU     = 2'b00;
    localparam [1:0] GENERATE = 2'b01;
    localparam [1:0] PLAY     = 2'b10;
    localparam [1:0] WIN      = 2'b11;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg frame_tick = 1'b0;
    reg start_game = 1'b0;
    reg regen_button = 1'b0;
    reg gen_busy = 1'b0;
    reg gen_done = 1'b0;
    reg in_goal = 1'b0;
    wire [1:0] game_state;
    wire gen_start;
    wire seed_capture;
    wire phys_init;
    wire phys_en;

    integer errors = 0;
    integer start_count = 0;
    integer seed_count = 0;
    integer init_count = 0;

    always #5 clk = ~clk;

    game_ctrl #(.START_IN_MENU(1'b1)) dut (
        .clk          (clk),
        .rst          (rst),
        .frame_tick   (frame_tick),
        .start_game   (start_game),
        .regen_button (regen_button),
        .gen_busy     (gen_busy),
        .gen_done     (gen_done),
        .in_goal      (in_goal),
        .game_state   (game_state),
        .gen_start    (gen_start),
        .seed_capture (seed_capture),
        .phys_init    (phys_init),
        .phys_en      (phys_en)
    );

    always @(posedge clk) begin
        if (!rst) begin
            if (gen_start) start_count = start_count + 1;
            if (seed_capture) seed_count = seed_count + 1;
            if (phys_init) init_count = init_count + 1;
        end
    end

    task pulse_frame;
        begin
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
        end
    endtask

    task wait_state;
        input [1:0] expected;
        integer guard;
        begin
            guard = 0;
            while ((game_state !== expected) && (guard < 30)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (game_state !== expected) begin
                $display("FAIL: timed out waiting for state %b; got %b", expected, game_state);
                errors = errors + 1;
            end
        end
    endtask

    task complete_generation;
        begin
            @(negedge clk); gen_busy = 1'b1; gen_done = 1'b1;
            @(negedge clk); gen_done = 1'b0;
            pulse_frame();
            if (game_state !== GENERATE) begin
                $display("FAIL: entered PLAY while gen_busy was still high");
                errors = errors + 1;
            end
            @(negedge clk); gen_busy = 1'b0;
            pulse_frame();
            wait_state(PLAY);
        end
    endtask

    task pulse_regen;
        begin
            @(negedge clk); regen_button = 1'b1;
            @(negedge clk); regen_button = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        if (game_state !== MENU) begin
            $display("FAIL: START_IN_MENU option did not enter MENU on reset");
            errors = errors + 1;
        end
        @(negedge clk); rst = 1'b0;
        @(negedge clk); start_game = 1'b1;
        pulse_frame();
        @(negedge clk); start_game = 1'b0;
        wait_state(GENERATE);

        wait (seed_capture === 1'b1);
        wait (gen_start === 1'b1);
        if (game_state !== GENERATE || phys_en !== 1'b0) begin
            $display("FAIL: startup generation state/physics enable incorrect");
            errors = errors + 1;
        end
        pulse_regen();
        if (game_state !== GENERATE) begin
            $display("FAIL: regenerate request was not ignored during GENERATE");
            errors = errors + 1;
        end

        complete_generation();
        if (phys_en !== 1'b1 || phys_init !== 1'b1) begin
            $display("FAIL: PLAY did not enable physics and initialize it");
            errors = errors + 1;
        end

        // The short button event is held until the next frame boundary.
        pulse_regen();
        if (game_state !== PLAY) begin
            $display("FAIL: controller changed state before frame_tick");
            errors = errors + 1;
        end
        pulse_frame();
        wait_state(GENERATE);
        pulse_regen(); // must not queue a third generation
        wait (gen_start === 1'b1);
        complete_generation();

        @(negedge clk); in_goal = 1'b1;
        pulse_frame();
        wait_state(WIN);
        if (phys_en !== 1'b0) begin
            $display("FAIL: physics remained enabled in WIN");
            errors = errors + 1;
        end
        @(negedge clk); in_goal = 1'b0;
        pulse_frame();
        wait_state(GENERATE);
        wait (gen_start === 1'b1);
        repeat (2) @(posedge clk);

        if (start_count != 3 || seed_count != 3 || init_count != 2) begin
            $display("FAIL: starts=%0d seed captures=%0d phys_init=%0d (expected 3,3,2)",
                     start_count, seed_count, init_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: game_ctrl startup, regeneration, busy gating, frame handoff, and WIN path");
        else
            $display("FAIL: game_ctrl had %0d errors", errors);
        $finish;
    end
endmodule
