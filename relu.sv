// ============================================================
// relu.sv
//
// FCCA - FPGA CNN Convolution Accelerator
//
// ReLU activation: passes positive/zero values through unchanged,
// zeroes out negative values. Implemented as a sign-bit check plus
// a mux - no multiplication, no lookup table.
//
// Purely combinational - no clock, reset, or handshaking.
// ============================================================

module relu (
    input  signed [35:0] conv_sum,
    output signed [35:0] relu_out
);

    // Bit [35] is the sign bit of a signed 36-bit two's complement
    // value: 1 means negative, 0 means positive or zero.
    assign relu_out = conv_sum[35] ? 36'sd0 : conv_sum;

endmodule
