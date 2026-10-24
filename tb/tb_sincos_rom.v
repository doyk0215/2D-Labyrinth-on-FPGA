`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// Self-checking testbench for sincos_rom (Story 2.2, trig table part).
// Checks all 4096 angles against a real-number model, the key angles
// exactly, the unit-circle identity, and the 1-clock latency.
module tb_sincos_rom;

    localparam integer MAX_ERR_LSB = 2;   // agreed tolerance, Q1.14 LSBs
    localparam real    PI          = 3.14159265358979323846;

    reg                          clk = 1'b0;
    reg  [`ANGLE_W-1:0]          angle = 0;
    wire signed [`TRIG_W-1:0]    sin_q;
    wire signed [`TRIG_W-1:0]    cos_q;

    always #5 clk = ~clk;

    sincos_rom dut (.clk(clk), .angle(angle), .sin_q(sin_q), .cos_q(cos_q));

    integer a, errors, max_err_sin, max_err_cos, e_s, e_c, id_err, max_id_err;
    integer exp_s, exp_c;
    real    theta;

    task check_key;
        input [`ANGLE_W-1:0] ang;
        input integer es;
        input integer ec;
        begin
            angle = ang;
            @(posedge clk); #1;
            if (sin_q !== es[`TRIG_W-1:0] || cos_q !== ec[`TRIG_W-1:0]) begin
                errors = errors + 1;
                $display("FAIL key angle %0d: sin=%0d (exp %0d) cos=%0d (exp %0d)",
                         ang, sin_q, es, cos_q, ec);
            end
        end
    endtask

    initial begin
        errors = 0; max_err_sin = 0; max_err_cos = 0; max_id_err = 0;
        repeat (3) @(posedge clk);

        // Key angles must be exact.
        check_key(12'd0,    0,      16384);
        check_key(12'd1024, 16384,  0);
        check_key(12'd2048, 0,     -16384);
        check_key(12'd3072, -16384, 0);

        // Latency: result for angle N appears one clock after N is applied.
        angle = 12'd512;
        @(posedge clk); #1;
        theta = 2.0 * PI * 512.0 / 4096.0;
        exp_s = $rtoi($floor(16384.0 * $sin(theta) + 0.5));
        if (sin_q !== exp_s[`TRIG_W-1:0]) begin
            errors = errors + 1;
            $display("FAIL latency: sin(512) = %0d, expected %0d one clock later", sin_q, exp_s);
        end

        // Full sweep of all 4096 angles.
        for (a = 0; a < 4096; a = a + 1) begin
            angle = a[`ANGLE_W-1:0];
            @(posedge clk); #1;
            theta = 2.0 * PI * a / 4096.0;
            exp_s = $rtoi($floor(16384.0 * $sin(theta) + 0.5));
            exp_c = $rtoi($floor(16384.0 * $cos(theta) + 0.5));
            e_s = sin_q - exp_s; if (e_s < 0) e_s = -e_s;
            e_c = cos_q - exp_c; if (e_c < 0) e_c = -e_c;
            if (e_s > max_err_sin) max_err_sin = e_s;
            if (e_c > max_err_cos) max_err_cos = e_c;
            if (e_s > MAX_ERR_LSB || e_c > MAX_ERR_LSB) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("FAIL angle %0d: sin=%0d (exp %0d) cos=%0d (exp %0d)",
                             a, sin_q, exp_s, cos_q, exp_c);
            end
            // Unit circle: sin^2 + cos^2 = 1.0 (2^28 in Q2.28), within 2*2*16384 ~ 65536
            id_err = sin_q * sin_q + cos_q * cos_q - (16384 * 16384);
            if (id_err < 0) id_err = -id_err;
            if (id_err > max_id_err) max_id_err = id_err;
            if (id_err > 4 * 16384) begin
                errors = errors + 1;
                if (errors < 10) $display("FAIL identity at angle %0d: error %0d", a, id_err);
            end
        end

        $display("max error: sin %0d LSB, cos %0d LSB (limit %0d); max identity error %0d",
                 max_err_sin, max_err_cos, MAX_ERR_LSB, max_id_err);
        if (errors == 0)
            $display("PASS: sincos_rom matches the model for all 4096 angles, key angles exact, 1-clock latency");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
