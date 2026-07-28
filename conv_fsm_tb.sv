// ============================================================
// conv_fsm_tb.sv
//
// Top-level testbench for conv_fsm. Runs two full convolution
// passes end to end (window_extraction -> mac_adder_tree -> relu
// -> output_array), at two different stride/padding configs, and
// checks every output cell against a numpy-computed ground truth.
//
// Clock: 50 MHz (20 ns period), matching the target discussed.
// ============================================================

`timescale 1ns/1ps

module conv_fsm_tb;

    reg clk = 0;
    reg rst;
    reg start;

    reg signed [17:0] image [0:7][0:7];

    reg signed [17:0] weight_00, weight_01, weight_02;
    reg signed [17:0] weight_10, weight_11, weight_12;
    reg signed [17:0] weight_20, weight_21, weight_22;

    reg [3:0] stride_reg, padding_reg;

    wire done;
    wire signed [35:0] output_array [0:11][0:11];
    wire [3:0] output_row_count, output_col_count;

    integer errors = 0;
    integer tests   = 0;
    integer r, c;

    // 50 MHz clock: 20 ns period
    always #10 clk = ~clk;

    conv_fsm dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .image(image),
        .weight_00(weight_00), .weight_01(weight_01), .weight_02(weight_02),
        .weight_10(weight_10), .weight_11(weight_11), .weight_12(weight_12),
        .weight_20(weight_20), .weight_21(weight_21), .weight_22(weight_22),
        .stride_reg(stride_reg),
        .padding_reg(padding_reg),
        .done(done),
        .output_array(output_array),
        .output_row_count(output_row_count),
        .output_col_count(output_col_count)
    );

    // Pulses start and waits for done, with a timeout safeguard.
    // (No array arguments - Icarus does not support unpacked array
    // ports on tasks, so the expected-value comparison is done
    // separately after calling this, using the module-level arrays.)
    task run_and_wait;
        input [8*30-1:0] label;
        input [3:0] exp_stride, exp_padding;
        integer wait_cycles;
        begin
            stride_reg = exp_stride;
            padding_reg = exp_padding;

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait_cycles = 0;
            while (!done && wait_cycles < 200) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (!done) begin
                errors = errors + 1;
                $display("FAIL [%0s]: TIMEOUT waiting for done", label);
            end
        end
    endtask

    // Compares output_array against expected_current (module-level
    // array, filled in by the caller before invoking this).
    task check_against_expected;
        input [8*30-1:0] label;
        input integer expected_size;
        begin
            if (output_row_count !== expected_size || output_col_count !== expected_size) begin
                errors = errors + 1;
                $display("FAIL [%0s]: output size mismatch - got %0dx%0d, expected %0dx%0d",
                    label, output_row_count, output_col_count, expected_size, expected_size);
            end else begin
                for (r = 0; r < expected_size; r = r + 1) begin
                    for (c = 0; c < expected_size; c = c + 1) begin
                        tests = tests + 1;
                        if (output_array[r][c] !== expected_current[r][c]) begin
                            errors = errors + 1;
                            $display("FAIL [%0s] at [%0d][%0d]: got %0d, expected %0d",
                                label, r, c, output_array[r][c], expected_current[r][c]);
                        end
                    end
                end
                if (errors == 0)
                    $display("PASS [%0s]: all %0dx%0d outputs correct", label, expected_size, expected_size);
            end
        end
    endtask

    integer expected_current [0:11][0:11];
    integer i, j;

    initial begin
        rst = 1;
        start = 0;
        stride_reg = 1;
        padding_reg = 0;

        // Image fill: image[r][c] = r*10 + c (same pattern used in
        // the window_extraction testbench)
        for (r = 0; r < 8; r = r + 1)
            for (c = 0; c < 8; c = c + 1)
                image[r][c] = r*10 + c;

        // Fixed kernel: horizontal-gradient / edge-detection style
        // [-1 0 1]
        // [-1 0 1]
        // [-1 0 1]
        weight_00 = -1; weight_01 = 0; weight_02 = 1;
        weight_10 = -1; weight_11 = 0; weight_12 = 1;
        weight_20 = -1; weight_21 = 0; weight_22 = 1;

        // Ground truth computed independently in Python (numpy-style
        // manual convolution + ReLU), not by re-deriving the RTL logic.

        // Release reset
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ---- Case A: stride 1, padding 0 -> 6x6, constant 6 everywhere ----
        // (a linear ramp image convolved with a gradient kernel
        // produces a constant result at every position)
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                expected_current[i][j] = 6;

        run_and_wait("stride1_pad0", 4'd1, 4'd0);
        check_against_expected("stride1_pad0", 6);

        // ---- Case B: stride 2, padding 1 -> 4x4 ----
        expected_current[0][0]=12;  expected_current[0][1]=4; expected_current[0][2]=4; expected_current[0][3]=4;
        expected_current[1][0]=63;  expected_current[1][1]=6; expected_current[1][2]=6; expected_current[1][3]=6;
        expected_current[2][0]=123; expected_current[2][1]=6; expected_current[2][2]=6; expected_current[2][3]=6;
        expected_current[3][0]=183; expected_current[3][1]=6; expected_current[3][2]=6; expected_current[3][3]=6;

        run_and_wait("stride2_pad1", 4'd2, 4'd1);
        check_against_expected("stride2_pad1", 4);

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED (%0d cells checked)", tests - errors, tests);
        else
            $display("%0d ERRORS across %0d cells checked", errors, tests);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
