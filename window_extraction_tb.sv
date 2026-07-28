// ============================================================
// window_extraction_tb.sv
//
// Standalone testbench for window_extraction. Focuses on the
// trickiest cases: zero padding/stride 1 baseline, the padding
// boundary (taps that fall outside the image), and non-default
// stride.
// ============================================================

`timescale 1ns/1ps

module window_extraction_tb;

    reg  signed [17:0] image [0:7][0:7];
    reg  [5:0] row_pos, col_pos;
    reg  [3:0] stride_reg, padding_reg;

    wire signed [17:0] pixel_00, pixel_01, pixel_02;
    wire signed [17:0] pixel_10, pixel_11, pixel_12;
    wire signed [17:0] pixel_20, pixel_21, pixel_22;

    integer errors = 0;
    integer tests   = 0;
    integer r, c;

    window_extraction dut (
        .image(image),
        .row_pos(row_pos),
        .col_pos(col_pos),
        .stride_reg(stride_reg),
        .padding_reg(padding_reg),
        .pixel_00(pixel_00), .pixel_01(pixel_01), .pixel_02(pixel_02),
        .pixel_10(pixel_10), .pixel_11(pixel_11), .pixel_12(pixel_12),
        .pixel_20(pixel_20), .pixel_21(pixel_21), .pixel_22(pixel_22)
    );

    // Checks all 9 outputs against 9 expected values in one shot
    task check_window;
        input [8*40-1:0] label;
        input signed [17:0] e00, e01, e02, e10, e11, e12, e20, e21, e22;
        begin
            #5;
            tests = tests + 1;
            if (pixel_00 !== e00 || pixel_01 !== e01 || pixel_02 !== e02 ||
                pixel_10 !== e10 || pixel_11 !== e11 || pixel_12 !== e12 ||
                pixel_20 !== e20 || pixel_21 !== e21 || pixel_22 !== e22) begin
                errors = errors + 1;
                $display("FAIL [%0s]:", label);
                $display("  got:      %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                    pixel_00, pixel_01, pixel_02, pixel_10, pixel_11, pixel_12, pixel_20, pixel_21, pixel_22);
                $display("  expected: %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                    e00, e01, e02, e10, e11, e12, e20, e21, e22);
            end else begin
                $display("PASS [%0s]", label);
            end
        end
    endtask

    initial begin
        // Fill the 8x8 image with row*10 + col, so each pixel value
        // is easy to predict by hand: image[r][c] = r*10 + c
        for (r = 0; r < 8; r = r + 1)
            for (c = 0; c < 8; c = c + 1)
                image[r][c] = r*10 + c;

        // ---- Case 1: stride 1, padding 0, top-left window ----
        // Window top-left = (0,0)*1 - 0 = (0,0). Should read the
        // real top-left 3x3 patch directly, no padding involved.
        stride_reg = 1; padding_reg = 0; row_pos = 0; col_pos = 0;
        check_window("stride1_pad0_topleft",
            0,1,2,
            10,11,12,
            20,21,22);

        // ---- Case 2: stride 1, padding 0, interior window ----
        // Window top-left = (2,3)*1 - 0 = (2,3).
        row_pos = 2; col_pos = 3;
        check_window("stride1_pad0_interior",
            23,24,25,
            33,34,35,
            43,44,45);

        // ---- Case 3: stride 1, padding 0, bottom-right window ----
        // Largest valid position for 8x8 input / 3x3 kernel / stride 1
        // is row_pos=col_pos=5 (0-indexed), window top-left = (5,5).
        row_pos = 5; col_pos = 5;
        check_window("stride1_pad0_bottomright",
            55,56,57,
            65,66,67,
            75,76,77);

        // ---- Case 4: padding 1, top-left window ----
        // Window top-left = (0,0)*1 - 1 = (-1,-1). The whole top row
        // and whole left column of this window fall outside the
        // image and must read as zero; only the bottom-right 2x2
        // sub-block of the window overlaps real image[0][0]..[1][1].
        stride_reg = 1; padding_reg = 1; row_pos = 0; col_pos = 0;
        check_window("pad1_topleft_corner",
            0,0,0,
            0,0,1,
            0,10,11);

        // ---- Case 5: padding 1, bottom-right window ----
        // With padding 1, output size = (8+2-3)/1+1 = 8, so valid
        // row_pos/col_pos go up to 7. At row_pos=col_pos=7:
        // window top-left = 7*1 - 1 = 6. Taps span image rows/cols
        // 6,7,8 -> row/col 8 is outside the image (zero).
        row_pos = 7; col_pos = 7;
        check_window("pad1_bottomright_corner",
            66,67,0,
            76,77,0,
            0,0,0);

        // ---- Case 6: stride 2, padding 0 ----
        // row_pos=1, col_pos=1 -> window top-left = 1*2 - 0 = (2,2)
        stride_reg = 2; padding_reg = 0; row_pos = 1; col_pos = 1;
        check_window("stride2_pad0",
            22,23,24,
            32,33,34,
            42,43,44);

        // ---- Case 7: stride 2 with padding 1 combined ----
        // row_pos=0, col_pos=0 -> window top-left = 0*2 - 1 = (-1,-1)
        // same top-left as case 4, so same expected pattern
        stride_reg = 2; padding_reg = 1; row_pos = 0; col_pos = 0;
        check_window("stride2_pad1_topleft",
            0,0,0,
            0,0,1,
            0,10,11);

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
