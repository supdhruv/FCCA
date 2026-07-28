// ============================================================
// mac_adder_tree_tb.sv
//
// Standalone testbench for mac_adder_tree.
// Feeds known pixel/kernel values, computes the expected sum in
// the testbench itself, and checks the module's output against it.
// ============================================================

`timescale 1ns/1ps

module mac_adder_tree_tb;

    // DUT inputs
    reg signed [17:0] pixel_00, pixel_01, pixel_02;
    reg signed [17:0] pixel_10, pixel_11, pixel_12;
    reg signed [17:0] pixel_20, pixel_21, pixel_22;

    reg signed [17:0] weight_00, weight_01, weight_02;
    reg signed [17:0] weight_10, weight_11, weight_12;
    reg signed [17:0] weight_20, weight_21, weight_22;

    // DUT output
    wire signed [35:0] conv_sum;

    integer errors = 0;
    integer tests   = 0;

    // Instantiate the DUT
    mac_adder_tree dut (
        .pixel_00(pixel_00), .pixel_01(pixel_01), .pixel_02(pixel_02),
        .pixel_10(pixel_10), .pixel_11(pixel_11), .pixel_12(pixel_12),
        .pixel_20(pixel_20), .pixel_21(pixel_21), .pixel_22(pixel_22),
        .weight_00(weight_00), .weight_01(weight_01), .weight_02(weight_02),
        .weight_10(weight_10), .weight_11(weight_11), .weight_12(weight_12),
        .weight_20(weight_20), .weight_21(weight_21), .weight_22(weight_22),
        .conv_sum(conv_sum)
    );

    // Reusable check task: loads a 3x3 pixel window + 3x3 kernel,
    // waits for combinational settle, computes the expected sum by
    // hand in the testbench, and compares against the DUT output.
    task run_case;
        input [8*40-1:0] label; // test case name, for display
        input signed [17:0] px00, px01, px02, px10, px11, px12, px20, px21, px22;
        input signed [17:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
        reg signed [35:0] expected;
        begin
            pixel_00 = px00; pixel_01 = px01; pixel_02 = px02;
            pixel_10 = px10; pixel_11 = px11; pixel_12 = px12;
            pixel_20 = px20; pixel_21 = px21; pixel_22 = px22;

            weight_00 = w00; weight_01 = w01; weight_02 = w02;
            weight_10 = w10; weight_11 = w11; weight_12 = w12;
            weight_20 = w20; weight_21 = w21; weight_22 = w22;

            #5; // allow combinational logic to settle

            expected = (px00*w00) + (px01*w01) + (px02*w02)
                     + (px10*w10) + (px11*w11) + (px12*w12)
                     + (px20*w20) + (px21*w21) + (px22*w22);

            tests = tests + 1;
            if (conv_sum !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0s]: expected %0d, got %0d", label, expected, conv_sum);
            end else begin
                $display("PASS [%0s]: conv_sum = %0d", label, conv_sum);
            end
        end
    endtask

    initial begin
        // Case 1: all zeros -> sum should be 0
        run_case("all_zeros",
            0,0,0, 0,0,0, 0,0,0,
            0,0,0, 0,0,0, 0,0,0);

        // Case 2: identity-like kernel (only center weight = 1, rest 0)
        // -> sum should equal the center pixel value only
        run_case("center_tap_only",
            1,2,3, 4,5,6, 7,8,9,
            0,0,0, 0,1,0, 0,0,0);

        // Case 3: all-ones kernel, small positive pixels
        // -> sum should equal the sum of all 9 pixels
        run_case("sum_all_pixels",
            1,2,3, 4,5,6, 7,8,9,
            1,1,1, 1,1,1, 1,1,1);

        // Case 4: signed / negative values mixed in
        // (edge-detection-like kernel: positive on one side, negative on the other)
        run_case("signed_edge_kernel",
            10,10,10, 10,10,10, 10,10,10,
            -1,0,1, -1,0,1, -1,0,1);
        // expected: every row contributes (-10 + 0 + 10) = 0 -> total 0

        // Case 5: negative pixels (e.g. after a hypothetical prior negative-producing stage)
        run_case("negative_pixels",
            -5,-4,-3, -2,-1,0, 1,2,3,
            2,2,2, 2,2,2, 2,2,2);

        // Case 6: near-max-magnitude 18-bit signed values, checking for overflow
        // 18-bit signed range: -131072 to 131071
        run_case("near_max_values",
            131071,131071,131071, 131071,131071,131071, 131071,131071,131071,
            1,1,1, 1,1,1, 1,1,1);

        // Case 7: near-min (most negative) 18-bit signed values
        run_case("near_min_values",
            -131072,-131072,-131072, -131072,-131072,-131072, -131072,-131072,-131072,
            1,1,1, 1,1,1, 1,1,1);

        // Case 8: mixed sign products, largest possible magnitude both ways
        run_case("max_swing_mixed",
            131071,-131072,131071, -131072,131071,-131072, 131071,-131072,131071,
            131071,131071,131071, 131071,131071,131071, 131071,131071,131071);

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
