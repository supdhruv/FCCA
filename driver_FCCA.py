"""
driver.py - FCCA (FPGA CNN Convolution Accelerator) Python driver

Runs on the PYNQ-Z2's ARM core under PYNQ. Talks to the
fcca_axi_wrapper IP over AXI-Lite using the register map agreed
during design:

    0x00  REG_ELEM_INDEX      (W) - element index for image/kernel loads
    0x04  REG_IMAGE_DATA      (W) - writes image_mem at REG_ELEM_INDEX
    0x08  REG_KERNEL_DATA     (W) - writes kernel_mem at REG_ELEM_INDEX
    0x0C  REG_STRIDE_PADDING  (W) - bits[3:0]=stride, bits[7:4]=padding
    0x10  REG_CONTROL         (W) - bit0=rst pulse, bit1=start pulse
    0x14  REG_STATUS          (R) - bit0=done, [7:4]=row_count, [11:8]=col_count
    0x18  REG_RESULT_INDEX    (W) - element index for result reads (0-143)
    0x1C  REG_RESULT_DATA     (R) - lower 32 bits of output_array at REG_RESULT_INDEX

Supported ranges (matching the hardware design's fixed limits):
    image:   8x8
    kernel:  3x3 (fixed, not resizable)
    stride:  1-4
    padding: 0-3
"""

import time
import numpy as np
from pynq import Overlay


class FCCAAccelerator:
    # Register offsets
    REG_ELEM_INDEX     = 0x00
    REG_IMAGE_DATA      = 0x04
    REG_KERNEL_DATA     = 0x08
    REG_STRIDE_PADDING  = 0x0C
    REG_CONTROL         = 0x10
    REG_STATUS          = 0x14
    REG_RESULT_INDEX    = 0x18
    REG_RESULT_DATA     = 0x1C

    IMAGE_SIZE  = 8
    KERNEL_SIZE = 3
    MAX_OUTPUT_SIZE = 12  # matches the hardware's fixed 12x12 output array bound

    def __init__(self, bitstream_path, ip_name="fcca_axi_wrapper_0"):
        """
        bitstream_path: path to the .bit file on the PYNQ-Z2 (the
                         matching .hwh file must sit alongside it).
        ip_name:        name of the AXI IP block as it appears in
                         the block design / overlay (check
                         Overlay(bitstream_path).ip_dict.keys() if
                         unsure - Vivado may auto-suffix this, e.g.
                         "fcca_axi_wrapper_0").
        """
        self.overlay = Overlay(bitstream_path)
        self.ip = getattr(self.overlay, ip_name)

    # -----------------------------------------------------------
    # Low-level register access
    # -----------------------------------------------------------
    def _write(self, offset, value):
        self.ip.write(offset, int(value) & 0xFFFFFFFF)

    def _read(self, offset):
        return self.ip.read(offset)

    # -----------------------------------------------------------
    # Loading data
    # -----------------------------------------------------------
    def load_image(self, image):
        """image: 8x8 array-like of integers (signed 18-bit range)."""
        image = np.asarray(image)
        if image.shape != (self.IMAGE_SIZE, self.IMAGE_SIZE):
            raise ValueError(f"image must be {self.IMAGE_SIZE}x{self.IMAGE_SIZE}, got {image.shape}")

        for r in range(self.IMAGE_SIZE):
            for c in range(self.IMAGE_SIZE):
                idx = r * self.IMAGE_SIZE + c
                self._write(self.REG_ELEM_INDEX, idx)
                # Mask to 18 bits so negative Python ints become the
                # correct two's complement pattern for the signed
                # 18-bit register on the RTL side.
                self._write(self.REG_IMAGE_DATA, int(image[r, c]) & 0x3FFFF)

    def load_kernel(self, kernel):
        """kernel: 3x3 array-like of integers (signed 18-bit range)."""
        kernel = np.asarray(kernel)
        if kernel.shape != (self.KERNEL_SIZE, self.KERNEL_SIZE):
            raise ValueError(f"kernel must be {self.KERNEL_SIZE}x{self.KERNEL_SIZE}, got {kernel.shape}")

        for r in range(self.KERNEL_SIZE):
            for c in range(self.KERNEL_SIZE):
                idx = r * self.KERNEL_SIZE + c
                self._write(self.REG_ELEM_INDEX, idx)
                self._write(self.REG_KERNEL_DATA, int(kernel[r, c]) & 0x3FFFF)

    def configure(self, stride=1, padding=0):
        if not (1 <= stride <= 4):
            raise ValueError("stride must be between 1 and 4")
        if not (0 <= padding <= 3):
            raise ValueError("padding must be between 0 and 3")
        value = (padding << 4) | stride
        self._write(self.REG_STRIDE_PADDING, value)

    # -----------------------------------------------------------
    # Control
    # -----------------------------------------------------------
    def reset(self):
        self._write(self.REG_CONTROL, 0x1)

    def start(self):
        self._write(self.REG_CONTROL, 0x2)

    def wait_done(self, timeout=1.0, poll_interval=0.0001):
        """Polls REG_STATUS until done (bit 0) is set. Returns the
        (row_count, col_count) reported by the hardware."""
        t_start = time.time()
        while time.time() - t_start < timeout:
            status = self._read(self.REG_STATUS)
            if status & 0x1:
                row_count = (status >> 4) & 0xF
                col_count = (status >> 8) & 0xF
                return row_count, col_count
            time.sleep(poll_interval)
        raise TimeoutError("FCCA did not assert done within timeout")

    # -----------------------------------------------------------
    # Reading results
    # -----------------------------------------------------------
    def read_result(self, row_count, col_count):
        """Reads back row_count x col_count result values. Values
        are always >= 0 (ReLU applied in hardware before storage),
        so no sign extension is needed on the 32-bit read - but
        note extremely large sums could in principle exceed 32
        bits and be truncated; this is not expected at FCCA's
        image/kernel value ranges."""
        result = np.zeros((row_count, col_count), dtype=np.int64)
        for r in range(row_count):
            for c in range(col_count):
                idx = r * self.MAX_OUTPUT_SIZE + c
                self._write(self.REG_RESULT_INDEX, idx)
                result[r, c] = self._read(self.REG_RESULT_DATA)
        return result

    # -----------------------------------------------------------
    # High-level convolve
    # -----------------------------------------------------------
    def convolve(self, image, kernel, stride=1, padding=0):
        """Loads image + kernel, configures stride/padding, runs
        one convolution + ReLU pass on hardware, and returns the
        result as a numpy array."""
        self.load_image(image)
        self.load_kernel(kernel)
        self.configure(stride, padding)
        self.start()
        row_count, col_count = self.wait_done()
        return self.read_result(row_count, col_count)

    # -----------------------------------------------------------
    # Software reference (for verification)
    # -----------------------------------------------------------
    @staticmethod
    def reference_convolve(image, kernel, stride=1, padding=0):
        """Plain numpy convolution + ReLU, computed independently
        of the hardware, for cross-checking results."""
        image = np.asarray(image)
        kernel = np.asarray(kernel)
        H, W = image.shape
        kh, kw = kernel.shape
        out_size = (H + 2 * padding - kh) // stride + 1

        result = np.zeros((out_size, out_size), dtype=np.int64)
        for orow in range(out_size):
            for ocol in range(out_size):
                base_row = orow * stride - padding
                base_col = ocol * stride - padding
                s = 0
                for i in range(kh):
                    for j in range(kw):
                        r, c = base_row + i, base_col + j
                        if 0 <= r < H and 0 <= c < W:
                            s += int(image[r, c]) * int(kernel[i, j])
                result[orow, ocol] = max(0, s)
        return result

    def verify(self, image, kernel, stride=1, padding=0):
        """Runs one convolution on hardware and checks it against
        the software reference. Returns (match: bool, hw_result, sw_result)."""
        hw_result = self.convolve(image, kernel, stride, padding)
        sw_result = self.reference_convolve(image, kernel, stride, padding)
        match = np.array_equal(hw_result, sw_result)
        return match, hw_result, sw_result

    # -----------------------------------------------------------
    # Benchmark suite (mirrors the matrix project's run_tests)
    # -----------------------------------------------------------
    def run_tests(self, num_tests=100, stride=1, padding=0,
                   pixel_low=0, pixel_high=255, weight_low=-10, weight_high=10, seed=None):
        """Runs num_tests random image/kernel convolutions on
        hardware, checks each against the software reference, and
        reports pass rate and timing statistics."""
        rng = np.random.default_rng(seed)
        passed = 0
        timings = []

        for i in range(num_tests):
            image = rng.integers(pixel_low, pixel_high, size=(self.IMAGE_SIZE, self.IMAGE_SIZE))
            kernel = rng.integers(weight_low, weight_high, size=(self.KERNEL_SIZE, self.KERNEL_SIZE))

            t0 = time.time()
            hw_result = self.convolve(image, kernel, stride, padding)
            t1 = time.time()

            sw_result = self.reference_convolve(image, kernel, stride, padding)

            if np.array_equal(hw_result, sw_result):
                passed += 1
            else:
                print(f"MISMATCH on test {i}:")
                print("  hw:\n", hw_result)
                print("  sw:\n", sw_result)

            timings.append(t1 - t0)

        timings = np.array(timings)
        print("--------------------------------------------------")
        print(f"{passed}/{num_tests} tests passed")
        print(f"Mean latency:   {timings.mean()*1e6:.2f} us")
        print(f"Std deviation:  {timings.std()*1e6:.2f} us")
        print(f"Min / Max:      {timings.min()*1e6:.2f} / {timings.max()*1e6:.2f} us")
        print("--------------------------------------------------")

        return passed, num_tests, timings


if __name__ == "__main__":
    # Example usage once the board is plugged in and the bitstream
    # + hwh files are copied over:
    #
    #   fcca = FCCAAccelerator("fcca_axi_wrapper.bit")
    #   fcca.reset()
    #
    #   image = [[r*10 + c for c in range(8)] for r in range(8)]
    #   kernel = [[-1, 0, 1], [-1, 0, 1], [-1, 0, 1]]
    #   match, hw_result, sw_result = fcca.verify(image, kernel, stride=1, padding=0)
    #   print("Match:", match)
    #   print(hw_result)
    #
    #   fcca.run_tests(num_tests=1000, stride=1, padding=0)
    pass
