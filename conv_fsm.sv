// ============================================================
// conv_fsm.sv
//
// FCCA - FPGA CNN Convolution Accelerator
//
// Top-level sequencer. Wires window_extraction -> mac_adder_tree
// -> relu into a single combinational chain, and on each clock
// cycle captures the result for the current output position into
// the output register array, then advances to the next position.
//
// Since all three sub-modules are purely combinational, a full
// convolution + activation result settles within one clock cycle -
// no separate fetch/compute/activate states are needed.
//
// Clock target: 50 MHz (20 ns period), chosen conservatively until
// post-synthesis timing analysis confirms actual critical path
// delay through the combinational chain.
//
// Supported ranges (fixed limits, not AXI-enforced by this module):
// padding_reg 0-3, stride_reg 1-4 -> output size 2x2 up to 12x12.
// ============================================================

module conv_fsm (
    input clk,
    input rst,
    input start,

    // Full 8x8 image (loaded externally, e.g. by the AXI wrapper)
    input signed [17:0] image [0:7][0:7],

    // Fixed 3x3 kernel weights (loaded externally)
    input signed [17:0] weight_00, weight_01, weight_02,
    input signed [17:0] weight_10, weight_11, weight_12,
    input signed [17:0] weight_20, weight_21, weight_22,

    input [3:0] stride_reg,
    input [3:0] padding_reg,

    output reg done,

    // Full 12x12 output array. Only the top-left
    // [0:output_row_count-1][0:output_col_count-1] region holds
    // valid data for the current run - the rest is stale/unused.
    output reg signed [35:0] output_array [0:11][0:11],

    // How much of output_array is actually valid for this run
    output reg [3:0] output_row_count,
    output reg [3:0] output_col_count
);

    // ---------------------------------------------------------
    // Output-size lookup table (replaces a real divider - only
    // 16 valid padding/stride combinations, precomputed by hand).
    // ---------------------------------------------------------
    function automatic [3:0] compute_output_size(
        input [3:0] padding,
        input [3:0] stride
    );
        begin
            case ({padding, stride})
                // padding = 0
                {4'd0,4'd1}: compute_output_size = 4'd6;
                {4'd0,4'd2}: compute_output_size = 4'd3;
                {4'd0,4'd3}: compute_output_size = 4'd2;
                {4'd0,4'd4}: compute_output_size = 4'd2;
                // padding = 1
                {4'd1,4'd1}: compute_output_size = 4'd8;
                {4'd1,4'd2}: compute_output_size = 4'd4;
                {4'd1,4'd3}: compute_output_size = 4'd3;
                {4'd1,4'd4}: compute_output_size = 4'd2;
                // padding = 2
                {4'd2,4'd1}: compute_output_size = 4'd10;
                {4'd2,4'd2}: compute_output_size = 4'd5;
                {4'd2,4'd3}: compute_output_size = 4'd4;
                {4'd2,4'd4}: compute_output_size = 4'd3;
                // padding = 3
                {4'd3,4'd1}: compute_output_size = 4'd12;
                {4'd3,4'd2}: compute_output_size = 4'd6;
                {4'd3,4'd3}: compute_output_size = 4'd4;
                {4'd3,4'd4}: compute_output_size = 4'd3;
                // Out of the supported range (padding > 3 or
                // stride > 4, or stride = 0): safe fallback.
                default: compute_output_size = 4'd1;
            endcase
        end
    endfunction

    // ---------------------------------------------------------
    // FSM state
    // ---------------------------------------------------------
    localparam IDLE = 2'd0;
    localparam RUN  = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [3:0] row_pos, col_pos; // current output position (output-space, not image-space)

    // ---------------------------------------------------------
    // Combinational datapath: window_extraction -> mac_adder_tree
    // -> relu, for whatever row_pos/col_pos currently are.
    // ---------------------------------------------------------
    wire signed [17:0] w_pixel_00, w_pixel_01, w_pixel_02;
    wire signed [17:0] w_pixel_10, w_pixel_11, w_pixel_12;
    wire signed [17:0] w_pixel_20, w_pixel_21, w_pixel_22;

    window_extraction u_window_extraction (
        .image(image),
        .row_pos({2'b00, row_pos}),
        .col_pos({2'b00, col_pos}),
        .stride_reg(stride_reg),
        .padding_reg(padding_reg),
        .pixel_00(w_pixel_00), .pixel_01(w_pixel_01), .pixel_02(w_pixel_02),
        .pixel_10(w_pixel_10), .pixel_11(w_pixel_11), .pixel_12(w_pixel_12),
        .pixel_20(w_pixel_20), .pixel_21(w_pixel_21), .pixel_22(w_pixel_22)
    );

    wire signed [35:0] w_conv_sum;

    mac_adder_tree u_mac_adder_tree (
        .pixel_00(w_pixel_00), .pixel_01(w_pixel_01), .pixel_02(w_pixel_02),
        .pixel_10(w_pixel_10), .pixel_11(w_pixel_11), .pixel_12(w_pixel_12),
        .pixel_20(w_pixel_20), .pixel_21(w_pixel_21), .pixel_22(w_pixel_22),
        .weight_00(weight_00), .weight_01(weight_01), .weight_02(weight_02),
        .weight_10(weight_10), .weight_11(weight_11), .weight_12(weight_12),
        .weight_20(weight_20), .weight_21(weight_21), .weight_22(weight_22),
        .conv_sum(w_conv_sum)
    );

    wire signed [35:0] w_relu_out;

    relu u_relu (
        .conv_sum(w_conv_sum),
        .relu_out(w_relu_out)
    );

    // ---------------------------------------------------------
    // Sequencer
    // ---------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            row_pos <= 4'd0;
            col_pos <= 4'd0;
            done <= 1'b0;
            output_row_count <= 4'd0;
            output_col_count <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        output_row_count <= compute_output_size(padding_reg, stride_reg);
                        output_col_count <= compute_output_size(padding_reg, stride_reg);
                        row_pos <= 4'd0;
                        col_pos <= 4'd0;
                        state <= RUN;
                    end
                end

                RUN: begin
                    // Capture the result for the CURRENT row_pos/col_pos
                    // (computed combinationally above) before advancing.
                    output_array[row_pos][col_pos] <= w_relu_out;

                    if (col_pos == output_col_count - 1'b1) begin
                        col_pos <= 4'd0;
                        if (row_pos == output_row_count - 1'b1) begin
                            state <= DONE;
                        end else begin
                            row_pos <= row_pos + 1'b1;
                        end
                    end else begin
                        col_pos <= col_pos + 1'b1;
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    if (start) begin
                        output_row_count <= compute_output_size(padding_reg, stride_reg);
                        output_col_count <= compute_output_size(padding_reg, stride_reg);
                        row_pos <= 4'd0;
                        col_pos <= 4'd0;
                        done <= 1'b0;
                        state <= RUN;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
