// ============================================================
// window_extraction.sv
//
// FCCA - FPGA CNN Convolution Accelerator
//
// Given the current output position (row_pos, col_pos) and the
// current stride/padding settings, extracts the 3x3 pixel window
// from the 8x8 image that mac_adder_tree needs for this step.
// Any tap that falls outside the real image (in the padded
// border) is substituted with zero.
//
// Purely combinational - no clock, reset, or handshaking. The FSM
// drives row_pos/col_pos and samples the 9 pixel outputs.
// ============================================================

module window_extraction (
    // Full 8x8 image, 2D unpacked array (row-major: image[row][col])
    input  signed [17:0] image [0:7][0:7],

    // Current output window's top-left corner, in output coordinate
    // space. 6 bits is generous headroom for any realistic output
    // size at the padding/stride ranges below.
    input  [5:0] row_pos,
    input  [5:0] col_pos,

    // AXI-configurable stride and padding
    input  [3:0] stride_reg,
    input  [3:0] padding_reg,

    // Extracted 3x3 window, matching mac_adder_tree's pixel_XX
    // input port names exactly so the two modules connect directly
    output signed [17:0] pixel_00, pixel_01, pixel_02,
    output signed [17:0] pixel_10, pixel_11, pixel_12,
    output signed [17:0] pixel_20, pixel_21, pixel_22
);

    // Top-left image coordinate this window maps to, before
    // per-tap offsets. Computed in signed arithmetic since this
    // can legitimately go negative when padding > 0 near the
    // top/left edge of the image - using unsigned here would
    // silently underflow/wrap and break the bounds check below.
    wire signed [15:0] base_row = $signed({1'b0, row_pos}) * $signed({1'b0, stride_reg}) - $signed({1'b0, padding_reg});
    wire signed [15:0] base_col = $signed({1'b0, col_pos}) * $signed({1'b0, stride_reg}) - $signed({1'b0, padding_reg});

    // Returns the real pixel if (img_row, img_col) falls inside
    // the 8x8 image, otherwise returns zero (the padding value).
    function automatic signed [17:0] fetch_pixel(
        input signed [15:0] img_row,
        input signed [15:0] img_col
    );
        begin
            if (img_row >= 0 && img_row <= 7 && img_col >= 0 && img_col <= 7)
                fetch_pixel = image[img_row[3:0]][img_col[3:0]];
            else
                fetch_pixel = 18'sd0;
        end
    endfunction

    // Each of the 9 taps is base_row/base_col plus its (i, j)
    // offset within the 3x3 window. Written explicitly (not via a
    // generate loop) to match the fixed, never-resizable 3x3 shape
    // and to keep the row/col naming self-documenting.
    assign pixel_00 = fetch_pixel(base_row + 0, base_col + 0);
    assign pixel_01 = fetch_pixel(base_row + 0, base_col + 1);
    assign pixel_02 = fetch_pixel(base_row + 0, base_col + 2);

    assign pixel_10 = fetch_pixel(base_row + 1, base_col + 0);
    assign pixel_11 = fetch_pixel(base_row + 1, base_col + 1);
    assign pixel_12 = fetch_pixel(base_row + 1, base_col + 2);

    assign pixel_20 = fetch_pixel(base_row + 2, base_col + 0);
    assign pixel_21 = fetch_pixel(base_row + 2, base_col + 1);
    assign pixel_22 = fetch_pixel(base_row + 2, base_col + 2);

endmodule
