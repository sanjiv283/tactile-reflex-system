"""tools/make_quartus_project.py (Quartus itself is not available, so only the generated project text is tested)."""
import glob, os, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_pins as C, make_quartus_project as Q

class Project(unittest.TestCase):
    def setUp(self): self.d = tempfile.mkdtemp()
    def fixture_reference(self):
        """SYNTHETIC reference with an arbitrary pin per port bit and GPIO[0..6]; for testing the flow only."""
        with open(os.path.join(ROOT, "rtl", "de2_115_top.v")) as fh: ports = C.top_ports(fh.read())
        gm = C.read_map(os.path.join(ROOT, "constraints", "gpio_map.txt")); names = [b for b in sorted(C.bits(ports)) if b not in gm] + sorted(set(gm.values()))
        ref = os.path.join(self.d, "ref.qsf")
        with open(ref, "w") as fh: fh.write("".join(f"set_location_assignment PIN_T{i} -to {n}\n" for i, n in enumerate(names)))
        with open(ref) as fh: reftext = fh.read()
        txt, miss = C.emit(ports, reftext, gm); self.assertEqual(miss, [])
        pins = os.path.join(self.d, "pins.qsf")
        with open(pins, "w") as fh: fh.write(txt)
        return pins, ref
    def test_refuses_without_pins(self): self.assertRaises(SystemExit, Q.build, os.path.join(self.d, "o1"), None, False)
    def test_a_refused_run_leaves_no_directory_behind(self):
        for pins in (None, os.path.join(ROOT, "constraints", "de2_115.qsf")):
            o = os.path.join(self.d, "refused"); self.assertRaises(SystemExit, Q.build, o, pins, False); self.assertFalse(os.path.exists(o))
    def test_refuses_unverified_pin_file(self): self.assertRaises(SystemExit, Q.build, os.path.join(self.d, "o2"), os.path.join(ROOT, "constraints", "de2_115.qsf"), False)
    def test_synthesis_only_trial_has_warning_banner_and_all_rtl(self):
        o = os.path.join(self.d, "o3"); os.makedirs(o); v, files = Q.build(o, None, True); self.assertFalse(v)
        with open(os.path.join(o, "tactile_reflex.qsf")) as fh: t = fh.read()
        self.assertIn("NOT VERIFIED", t); self.assertIn("NOT FOR PROGRAMMING", t)
        want = sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "rtl", "*.v"))); self.assertEqual(files, want)
        for f in want: self.assertIn(f"rtl/{f}", t)
        self.assertTrue(os.path.exists(os.path.join(o, "rtl", "force_lut.mem"))); self.assertIn("EP4CE115F29C7", t); self.assertIn("TOP_LEVEL_ENTITY de2_115_top", t)
    def test_verified_pins_flow_with_synthetic_reference(self):
        pins, ref = self.fixture_reference(); o = os.path.join(self.d, "o4"); os.makedirs(o); v, _ = Q.build(o, pins, False, ref); self.assertTrue(v)
        with open(os.path.join(o, "tactile_reflex.qsf")) as fh: t = fh.read()
        self.assertIn("VERIFIED AGAINST A SUPPLIED TERASIC REFERENCE", t); self.assertIn("-to ESTOP_EXT_N", t)
    def test_tampered_pin_is_refused(self):
        pins, ref = self.fixture_reference()
        with open(pins) as fh: t = fh.read()
        with open(pins, "w") as fh: fh.write(t.replace("-to CLOCK_50", "-to CLOCK_50x", 1).replace("PIN_T0 ", "PIN_ZZ ", 1))
        self.assertRaises(SystemExit, Q.build, os.path.join(self.d, "o5"), pins, False, ref)

if __name__ == "__main__": unittest.main()
