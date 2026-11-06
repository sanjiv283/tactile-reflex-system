"""Pins the documented ADC-delay tolerance of the RTL in simulation (H-16). If this fails, the MISO structure, the ADC model or tb_top changed: re-measure with
tools/adc_timing_sweep.py and update HAZARD_ANALYSIS.md H-16, VERIFICATION_REPORT.md and the paper. Skipped without iverilog.
It does NOT show anything about the real ADC: only that the numbers quoted in the documents are the ones the simulation produces."""
import os, shutil, sys, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
class AdcTiming(unittest.TestCase):
    @unittest.skipUnless(shutil.which("iverilog") and shutil.which("vvp"), "iverilog not installed")
    def test_documented_tolerances(self):
        import adc_timing_sweep as S
        from concurrent.futures import ThreadPoolExecutor
        jobs = [("with_synchroniser", 20), ("with_synchroniser", 22), ("without_synchroniser", 60), ("without_synchroniser", 62), ("with_synchroniser", 0)]
        with ThreadPoolExecutor(4) as ex: r = {(v, d): x["result"] for v, d, x in ex.map(S.run_one, jobs)}
        self.assertEqual(r[("with_synchroniser", 0)], "PASS")
        self.assertEqual(r[("with_synchroniser", 20)], "PASS"); self.assertNotEqual(r[("with_synchroniser", 22)], "PASS")          # tolerance with the synchroniser: 20 ns
        self.assertEqual(r[("without_synchroniser", 60)], "PASS"); self.assertNotEqual(r[("without_synchroniser", 62)], "PASS")    # tolerance without it: 60 ns
if __name__ == "__main__": unittest.main()
