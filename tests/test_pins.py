"""tools/check_pins.py. The 'reference' files below are SYNTHETIC FIXTURES for testing the checker; they are not Terasic data
and their pin names are arbitrary."""
import json, os, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_pins as C

RTL = ") (\n input wire CLK, input wire [1:0] KEY, output wire [2:0] LED, output wire PWM\n);\n"
REF = "set_location_assignment PIN_A1 -to CLK\nset_location_assignment PIN_A2 -to KEY[0]\nset_location_assignment PIN_A3 -to KEY[1]\n" + "".join(f"set_location_assignment PIN_B{i} -to LED[{i}]\n" for i in range(3)) + "set_location_assignment PIN_C9 -to GPIO[0]\n"
GOOD = REF.replace("GPIO[0]", "PWM").replace("PIN_C9", "PIN_C9")

class Pins(unittest.TestCase):
    ports = C.top_ports(RTL)
    def test_port_parser(self): self.assertEqual(self.ports, {"CLK": 1, "KEY": 2, "LED": 3, "PWM": 1})
    def test_real_top_has_expected_bits(self):
        with open(os.path.join(ROOT, "rtl", "de2_115_top.v")) as fh: p = C.top_ports(fh.read())
        self.assertEqual((p["KEY"], p["LEDR"], p["LEDG"], p["CLOCK_50"]), (4, 18, 9, 1)); self.assertEqual(len(C.bits(p)), 41)
    def test_unassigned_reported_not_hidden(self):
        r = C.check("set_location_assignment PIN_A1 -to CLK\n", self.ports); self.assertIn("PWM", r["unassigned"]); self.assertIn("LED[2]", r["unassigned"])
    def test_duplicate_pin_and_unknown_port(self):
        r = C.check("set_location_assignment PIN_A1 -to CLK\nset_location_assignment PIN_A1 -to KEY[0]\nset_location_assignment PIN_Z9 -to NOPE\n", self.ports)
        self.assertEqual(len(r["errors"]), 2)
    def test_comments_are_ignored(self):
        r = C.check("# set_location_assignment PIN_A1 -to CLK\n", self.ports); self.assertIn("CLK", r["unassigned"])
    def test_verification_against_reference(self):
        ok = C.check(GOOD.replace("PWM", "PWM"), self.ports, GOOD)
        self.assertEqual((ok["mismatches"], ok["errors"], ok["unassigned"]), ([], [], [])); self.assertEqual(len(ok["verified"]), 7)
    def test_mismatch_detected(self):
        r = C.check(GOOD.replace("PIN_A2", "PIN_Q7"), self.ports, GOOD); self.assertEqual(len(r["mismatches"]), 1); self.assertIn("KEY[0]", r["mismatches"][0])
    def test_gpio_map_and_emit(self):
        rtl_ports = {"CLK": 1, "KEY": 2, "LED": 3, "PWM": 1}
        txt, miss = C.emit(rtl_ports, REF, {"PWM": "GPIO[0]"}); self.assertEqual(miss, [])
        self.assertIn("set_location_assignment PIN_C9 -to PWM", txt); self.assertIn("PIN_B2 -to LED[2]", txt)
        r = C.check(txt, rtl_ports, REF, {"PWM": "GPIO[0]"}); self.assertEqual((r["mismatches"], r["errors"], r["unassigned"], r["unverified"]), ([], [], [], []))
    def test_emit_reports_missing_reference_entries(self):
        txt, miss = C.emit(self.ports, "set_location_assignment PIN_A1 -to CLK\n", {}); self.assertIn("PWM", miss)
    def test_cli_status_text_and_exit_codes(self):
        d = tempfile.mkdtemp(); rtl = os.path.join(d, "t.v"); q = os.path.join(d, "a.qsf"); ref = os.path.join(d, "ref.qsf"); j = os.path.join(d, "o.json")
        for p, t in ((rtl, RTL), (q, GOOD.replace("GPIO[0]", "PWM")), (ref, GOOD.replace("GPIO[0]", "PWM"))):
            with open(p, "w") as fh: fh.write(t)
        base = ["--rtl", rtl, "--qsf", q, "--map", os.path.join(d, "none"), "--json", j]
        self.assertEqual(C.main(base), 0)
        with open(j) as fh: self.assertEqual(json.load(fh)["status"], "NOT VERIFIED AGAINST THE BOARD")
        self.assertEqual(C.main(base + ["--strict"]), 1)
        self.assertEqual(C.main(base + ["--reference", ref, "--strict"]), 0)
        with open(j) as fh: self.assertEqual(json.load(fh)["status"], "VERIFIED AGAINST REFERENCE")
        with open(q, "w") as fh: fh.write(GOOD.replace("PIN_A2", "PIN_Q7"))
        self.assertEqual(C.main(base + ["--reference", ref]), 1)

if __name__ == "__main__": unittest.main()
