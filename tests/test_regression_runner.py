"""Negative and positive tests for tools/run_regression.py: the runner must FAIL for every kind of broken testbench."""
import os, sys, tempfile, unittest, shutil

def write(path, text):
    with open(path, "w") as fh: fh.write(text)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import run_regression as rr

TB = {
 "ok": ('module tb_ok; initial begin $display("TB tb_ok: PASS 3 FAIL 0 VECTORS 0"); $finish; end endmodule', "tb_ok", True, ""),
 "no_vectors_field": ('module tb_nv; initial begin $display("TB tb_nv: PASS 3 FAIL 0"); $finish; end endmodule', "tb_nv", False, "VECTORS"),
 "ok_with_vectors": ('module tb_ok; initial begin $display("TB tb_ok: PASS 5 FAIL 0 VECTORS 4720"); $finish; end endmodule', "tb_ok", True, ""),
 "failing": ('module tb_fail; initial begin $display("FAIL: broken"); $display("TB tb_fail: PASS 1 FAIL 1"); $finish; end endmodule', "tb_fail", False, "assertion(s) failed"),
 "no_summary": ('module tb_nosum; initial begin $display("hello"); $finish; end endmodule', "tb_nosum", False, "found 0"),
 "pass_zero": ('module tb_zero; initial begin $display("TB tb_zero: PASS 0 FAIL 0"); $finish; end endmodule', "tb_zero", False, "no assertion executed"),
 "compile_error": ('module tb_ce; initial begin $display("x") $finish; end endmodule', "tb_ce", False, "compile error"),
 "hang": ('module tb_hang; initial begin forever #1; end endmodule', "tb_hang", False, "timeout"),
 "wrong_name": ('module tb_w; initial begin $display("TB tb_other: PASS 2 FAIL 0"); $finish; end endmodule', "tb_wrongname", False, "manifest expects"),
 "two_summaries": ('module tb_two; initial begin $display("TB tb_two: PASS 1 FAIL 0"); $display("TB tb_two: PASS 1 FAIL 0"); $finish; end endmodule', "tb_two", False, "found 2"),
 "tb_timeout_line": ('module tb_to; initial begin $display("TB tb_to: TIMEOUT"); $finish; end endmodule', "tb_to", False, "TIMEOUT"),
 "mismatch_line": ('module tb_mm; initial begin $display("MISMATCH i=3"); $display("TB tb_mm: PASS 1 FAIL 0"); $finish; end endmodule', "tb_mm", False, "output line"),
}

class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(); os.makedirs(self.d + "/rtl"); os.makedirs(self.d + "/tb")
        write(self.d + "/rtl/dummy.v", "module dummy(input a, output b); assign b = a; endmodule\n")
        write(self.d + "/tb/ad7476_model.v", "module ad7476_model_unused; endmodule\n")
        write(self.d + "/tb/safety_monitor.v", "module safety_monitor_unused; endmodule\n")
    def tearDown(self): shutil.rmtree(self.d, ignore_errors=True)
    def run_one(self, key):
        src, expect, _, _ = TB[key]; write(self.d + f"/tb/tb_{key}.v", src)
        return rr.run_testbench(dict(id=key, tb=f"tb/tb_{key}.v", plusargs=[], expect=expect), self.d, self.d + "/build", timeout=3, strict_warnings=True)
    def test_each_case(self):
        for key, (_, _, should_pass, why) in TB.items():
            with self.subTest(case=key):
                r = self.run_one(key)
                self.assertEqual(r["status"] == "PASS", should_pass, f"{key}: {r}")
                if not should_pass: self.assertTrue(any(why in p for p in r["problems"]), f"{key}: expected '{why}' in {r['problems']}")
    def test_vectors_extra_is_reported(self):
        self.assertEqual(self.run_one("ok_with_vectors")["extra"], "VECTORS 4720")
    def test_main_exit_status(self):
        # a manifest with one good and one failing testbench -> non-zero exit; only good -> zero
        for k in ("ok", "failing"): write(self.d + f"/tb/tb_{k}.v", TB[k][0])
        man = self.d + "/m.txt"
        write(man, "ok | tb/tb_ok.v | | tb_ok\nfailing | tb/tb_failing.v | | tb_fail\n")
        self.assertEqual(rr.main(["--root", self.d, "--manifest", man, "--log", self.d + "/l.txt", "--json", self.d + "/j.json", "--builddir", self.d + "/b", "--timeout", "5"]), 1)
        write(man, "ok | tb/tb_ok.v | | tb_ok\n")
        self.assertEqual(rr.main(["--root", self.d, "--manifest", man, "--log", self.d + "/l.txt", "--json", self.d + "/j.json", "--builddir", self.d + "/b", "--timeout", "5"]), 0)
    def test_manifest_rejects_duplicates_and_bad_lines(self):
        p = self.d + "/m.txt"; write(p, "a | tb/x.v | | tb_x\na | tb/y.v | | tb_y\n")
        with self.assertRaises(ValueError): rr.load_manifest(p)
        write(p, "only | three | fields\n")
        with self.assertRaises(ValueError): rr.load_manifest(p)
    def test_repository_manifest_matches_testbench_files(self):
        entries = rr.load_manifest(os.path.join(ROOT, "sim", "testbenches.txt"))
        listed = {e["tb"] for e in entries}
        on_disk = {"tb/" + f for f in os.listdir(os.path.join(ROOT, "tb")) if f.startswith("tb_") and f.endswith(".v")}
        self.assertEqual(listed, on_disk, "every tb/tb_*.v must be in sim/testbenches.txt (and vice versa)")

if __name__ == "__main__": unittest.main()
