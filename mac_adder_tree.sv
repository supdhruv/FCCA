// ============================================================
// mac_adder_tree.sv
//
// FCCA - FPGA CNN Convolution Accelerator
//
// Takes one already-extracted 3x3 window of pixels and the 3x3
// kernel, multiplies element-wise, and sums the 9 products using
// a 4-stage binary adder tree with zero-injection (so every stage
// pairs cleanly: 9 -> 5 -> 3 -> 2 -> 1).
//
// Purely combinational - no clock, reset, or handshaking. This
// module knows nothing about row/col position, stride, or padding;
// that is handled upstream by the window extraction logic.
// ============================================================

module mac_adder_tree (
    // Pixel window (row-major: pixel_RC, R = row, C = col)
    input  signed [17:0] pixel_00, pixel_01, pixel_02,
    input  signed [17:0] pixel_10, pixel_11, pixel_12,
    input  signed [17:0] pixel_20, pixel_21, pixel_22,

    // Kernel weights (row-major, same layout as pixels)
    input  signed [17:0] weight_00, weight_01, weight_02,
    input  signed [17:0] weight_10, weight_11, weight_12,
    input  signed [17:0] weight_20, weight_21, weight_22,

    // Raw accumulated convolution sum for this window position
    // (pre-activation - ReLU is applied outside this module)
    output signed [35:0] conv_sum
);

    // Constant zero used purely for zero-injection padding at each
    // adder-tree stage. Synthesis optimizes "x + ZERO" down to a
    // plain wire, so this costs no extra LUTs or registers.
    localparam signed [35:0] ZERO = 36'sd0;

    // ---------------------------------------------------------
    // Stage 0: 9 parallel multiplies
    // Two signed 18-bit operands -> signed 36-bit product each
    // ---------------------------------------------------------
    wire signed [35:0] p00 = pixel_00 * weight_00;
    wire signed [35:0] p01 = pixel_01 * weight_01;
    wire signed [35:0] p02 = pixel_02 * weight_02;
    wire signed [35:0] p10 = pixel_10 * weight_10;
    wire signed [35:0] p11 = pixel_11 * weight_11;
    wire signed [35:0] p12 = pixel_12 * weight_12;
    wire signed [35:0] p20 = pixel_20 * weight_20;
    wire signed [35:0] p21 = pixel_21 * weight_21;
    wire signed [35:0] p22 = pixel_22 * weight_22;

    // ---------------------------------------------------------
    // Stage 1: 9 products + 1 injected zero = 10 values -> 5 sums
    // ---------------------------------------------------------
    wire signed [35:0] s1_0 = p00 + p01;
    wire signed [35:0] s1_1 = p02 + p10;
    wire signed [35:0] s1_2 = p11 + p12;
    wire signed [35:0] s1_3 = p20 + p21;
    wire signed [35:0] s1_4 = p22 + ZERO;

    // ---------------------------------------------------------
    // Stage 2: 5 sums + 1 injected zero = 6 values -> 3 sums
    // ---------------------------------------------------------
    wire signed [35:0] s2_0 = s1_0 + s1_1;
    wire signed [35:0] s2_1 = s1_2 + s1_3;
    wire signed [35:0] s2_2 = s1_4 + ZERO;

    // ---------------------------------------------------------
    // Stage 3: 3 sums + 1 injected zero = 4 values -> 2 sums
    // ---------------------------------------------------------
    wire signed [35:0] s3_0 = s2_0 + s2_1;
    wire signed [35:0] s3_1 = s2_2 + ZERO;

    // ---------------------------------------------------------
    // Stage 4: final combine, 2 values -> 1 sum
    // ---------------------------------------------------------
    assign conv_sum = s3_0 + s3_1;

endmodule
