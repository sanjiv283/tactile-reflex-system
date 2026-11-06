"""Host-in-the-loop co-simulation (real host code vs real RTL in Icarus Verilog). Skipped when iverilog is missing."""
import json, os, shutil, sys, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
class Cosim(unittest.TestCase):
    @unittest.skipUnless(shutil.which("iverilog") and shutil.which("vvp"), "iverilog not installed")
    def test_host_and_rtl_agree(self):
        import cosim_host_rtl as C
        self.assertEqual(C.main(), 0)
        with open(os.path.join(ROOT, "results", "cosim_report.json")) as fh: r = json.load(fh)
        self.assertEqual((r["result"], r["host_bytes_dropped"], r["problems"]), ("PASS", 0, []))
        self.assertGreaterEqual(r["host_frames_decoded"], r["telemetry_frames"] - 2)
        for tag, c in r["passes"].items():                                   # coverage minima, restated here so lowering them in the tool is visible
            self.assertGreaterEqual(c["checked"], 100, tag); self.assertGreaterEqual(c["over_limit"], 12, tag); self.assertGreaterEqual(c["estop_pressed"], 8, tag)
            self.assertGreaterEqual(c["sensor_fault_active"], 6, tag); self.assertGreaterEqual(c["hysteresis_band"], 6, tag)
        self.assertEqual(r["passes"]["B"]["classes"], [0, 1, 2, 3])
        self.assertGreaterEqual(r["passes"]["C"]["ai_capped"], 10); self.assertGreaterEqual(r["passes"]["D"]["ai_capped"], 10)
        self.assertEqual(set(r["packet_types_in_F"]), {"good", "badchk", "badhdr", "garbage", "incons"})
    @unittest.skipUnless(shutil.which("iverilog") and shutil.which("vvp"), "iverilog not installed")
    def test_it_detects_injected_faults(self):
        import cosim_negative_controls as N
        res = N.run(["M24", "M20"])                    # checksum ignored (needs the corrupted-link pass) and heartbeat timeout disabled (needs the host-dies pass)
        self.assertTrue(all(v["detected"] for v in res.values()), res)
if __name__ == "__main__": unittest.main()
