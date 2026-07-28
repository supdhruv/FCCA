# FCCA
For the FCCA- FPGA CNN convolution accelerator project

Designed and implemented a CNN convolution accelerator on the PYNQ-Z2 (Zynq XC7Z020) FPGA, targeting a fixed 3×3 kernel over an 8×8 image with ReLU activation. Built five SystemVerilog modules (mac_adder_tree, relu, window_extraction, conv_fsm, fcca_axi_wrapper) with AXI-Lite integration for runtime-configurable stride and padding. Verified functionality in Icarus Verilog and Vivado behavioral simulation, then closed timing at 20 MHz post-implementation (WNS +10.909 ns) after an initial 50 MHz target failed timing closure. Used signed 18-bit inputs and 36-bit accumulators to align with the FPGA's DSP48E1 primitive widths. Wrote a Python driver (FCCAAccelerator) following a load→start→poll→read register-mapped control pattern for PYNQ-based deployment. Architecture and workflow built on a prior AXI-Lite matrix multiplication accelerator project, also deployed on PYNQ-Z2.

Skills used: SystemVerilog, FPGA Design, AXI-Lite, Digital Design, Vivado, Icarus Verilog, Python, PYNQ, Hardware Verification, RTL Design
