// ============================================================
// relu_tb.sv
//
// Standalone testbench for relu. Covers negative, positive, and
// zero cases, plus boundary/extreme values.
// ============================================================

`timescale 1ns/1ps

module relu_tb;

    reg  signed [35:0] conv_sum;
    wire signed [35:0] relu_out;

    integer errors = 0;
    integer tests   = 0;

    relu dut (
        .conv_sum(conv_sum),
        .relu_out(relu_out)
    );

    task run_case;
        input [8*30-1:0] label;
        input signed [35:0] in_val;
        input signed [35:0] expected;
        begin
            conv_sum = in_val;
            #5;
            tests = tests + 1;
            if (relu_out !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0s]: in=%0d expected=%0d got=%0d", label, in_val, expected, relu_out);
            end else begin
                $display("PASS [%0s]: in=%0d -> relu_out=%0d", label, in_val, relu_out);
            end
        end
    endtask

    initial begin
        // Zero stays zero
        run_case("zero", 0, 0);

        // Small positive passes through unchanged
        run_case("small_positive", 42, 42);

        // Small negative gets zeroed
        run_case("small_negative", -42, 0);

        // Largest possible positive 36-bit signed value passes through
        run_case("max_positive", 36'sd34359738367, 36'sd34359738367);

        // Most negative possible 36-bit signed value gets zeroed
        run_case("min_negative", -36'sd34359738368, 0);

        // Value of exactly -1 gets zeroed (boundary just below zero)
        run_case("minus_one", -1, 0);

        // Value of exactly 1 passes through (boundary just above zero)
        run_case("plus_one", 1, 1);

        // A realistic mid-range value from the mac_adder_tree tests
        // (max_swing_mixed case: 17179082757, positive -> passes through)
        run_case("realistic_positive", 36'sd17179082757, 36'sd17179082757);

        // A realistic negative value (negative_pixels case: -18 -> zeroed)
        run_case("realistic_negative", -18, 0);

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
