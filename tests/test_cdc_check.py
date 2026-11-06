"""tools/cdc_check.py must flag every kind of unsynchronised boundary input, including a NEW one, and accept the real RTL and correct new synchronisers."""
import os, shutil, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import cdc_check as C

class Cdc(unittest.TestCase):
    def setUp(self): self.d = tempfile.mkdtemp(); shutil.copytree(os.path.join(ROOT, "rtl"), os.path.join(self.d, "rtl"))
    def tearDown(self): shutil.rmtree(self.d, ignore_errors=True)
    def edit(self, f, old, new, count=1):
        p = os.path.join(self.d, "rtl", f)
        with open(p) as fh: t = fh.read()
        assert t.count(old) >= 1, (f, old); t = t.replace(old, new, count)
        with open(p, "w") as fh: fh.write(t)
    def run_check(self): return C.check(os.path.join(self.d, "rtl"), ["de2_115_top", "tactile_reflex_top"])
    def test_real_rtl_passes(self):
        _, rep, viol = self.run_check(); self.assertEqual(viol, []); self.assertEqual({r[1] for r in rep if r[2] == "unused"}, {"KEY[2]"})
        self.assertGreaterEqual(sum(1 for r in rep if r[2] == "sync"), 25)
    def test_new_unlisted_input_raw_flop_is_flagged(self):
        self.edit("de2_115_top.v", "wire [15:0] ai_gpio;", "wire [15:0] ai_gpio; reg raw_k2; always @(posedge CLOCK_50) raw_k2 <= KEY[2];")
        _, _, viol = self.run_check(); self.assertTrue(any("KEY" in v for v in viol), viol)
    def test_new_input_port_used_combinationally_is_flagged(self):
        self.edit("de2_115_top.v", "input  wire        UART_RXD,", "input  wire        UART_RXD,\n    input  wire        NEW_IN,")
        self.edit("de2_115_top.v", "wire [15:0] ai_gpio;", "wire [15:0] ai_gpio; wire mix = NEW_IN & ESTOP_EXT_N; wire sink = mix;")
        _, _, viol = self.run_check(); self.assertTrue(any("NEW_IN" in v for v in viol), viol)
    def test_new_input_with_a_correct_two_flop_synchroniser_is_accepted(self):
        self.edit("de2_115_top.v", "input  wire        UART_RXD,", "input  wire        UART_RXD,\n    input  wire        NEW_IN,")
        self.edit("de2_115_top.v", "wire [15:0] ai_gpio;", "wire [15:0] ai_gpio; reg [1:0] ns; always @(posedge CLOCK_50) ns <= {ns[0], NEW_IN}; wire used = ns[1];")
        _, _, viol = self.run_check(); self.assertEqual(viol, [])
    def test_synchroniser_bypassed_by_reading_stage_one(self):
        self.edit("tactile_reflex_top.v", ".adc_miso(ms[1])", ".adc_miso(ms[0])"); _, _, viol = self.run_check(); self.assertTrue(any("adc_miso" in v for v in viol), viol)
    def test_synchroniser_removed_from_core_input(self):
        self.edit("tactile_reflex_top.v", ".adc_miso(ms[1])", ".adc_miso(adc_miso)"); _, _, viol = self.run_check(); self.assertTrue(any("adc_miso" in v for v in viol), viol)
    def test_estop_chain_broken(self):
        self.edit("tactile_reflex_top.v", ".estop_n(es[1])", ".estop_n(estop_n)"); _, _, viol = self.run_check(); self.assertTrue(any("estop_n" in v for v in viol), viol)
    def test_wrapper_reset_connected_raw(self):
        self.edit("de2_115_top.v", "reset_sync u_rst (.clk(CLOCK_50), .arst_n(KEY[3]), .rst_n(rst_n));", "assign rst_n = KEY[3];"); _, _, viol = self.run_check(); self.assertTrue(any("KEY" in v for v in viol), viol)
    def test_uart_receiver_capture_removed(self):
        self.edit("uart_rx.v", "s <= {s[0], rxd};", "s <= {s[0], 1'b1}; if (!rxd) sh <= 8'd0;"); _, _, viol = self.run_check(); self.assertTrue(any("UART_RXD" in v or "rxd" in v for v in viol), viol)
    def test_stray_async_reset_flop_is_flagged(self):
        with open(os.path.join(self.d, "rtl", "stray.v"), "w") as fh: fh.write("module stray(input clk, input rst_n, input d, output reg q);\n always @(posedge clk or negedge rst_n) if (!rst_n) q <= 1'b0; else q <= d;\nendmodule\n")
        _, _, viol = self.run_check(); self.assertTrue(any("stray" in v for v in viol), viol)
    def test_second_clock_is_flagged(self):
        with open(os.path.join(self.d, "rtl", "stray.v"), "w") as fh: fh.write("module stray(input clk2, input d, output reg q);\n always @(posedge clk2) q <= d;\nendmodule\n")
        _, _, viol = self.run_check(); self.assertTrue(any("unexpected clock" in v for v in viol), viol)

if __name__ == "__main__": unittest.main()
