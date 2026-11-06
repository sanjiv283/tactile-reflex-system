"""tools/calibrate.py on SYNTHETIC calibration data (a made-up saturating curve + noise); proves the arithmetic and the refusals, says nothing about any real sensor."""
import csv, json, os, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import numpy as np, calibrate as K

def synth(loads, reps=5, seed=0, noise=3.0, hyst=0.0, down=True, gain=1.0, sat_at=None):
    rng = np.random.default_rng(seed); rows = []
    curve = lambda m: gain * 4000 * (1 - np.exp(-m / 900.0))
    for m in loads:
        for k in range(reps): rows.append((f"u{k}", "up", m, round(float(np.clip(curve(m) + rng.normal(0, noise), 0, 4095)))))
        if down:
            for k in range(reps): rows.append((f"d{k}", "down", m, round(float(np.clip(curve(m) + hyst + rng.normal(0, noise), 0, 4095)))))
    return rows

class Cal(unittest.TestCase):
    loads = [0, 100, 250, 500, 800, 1200, 1800, 2500]
    def test_recommendation_is_below_counts_at_limit_and_ordered(self):
        r = K.analyse(synth(self.loads, hyst=12), limit_n=15.0)   # 15 N ~ 1530 g
        rec = r["recommended"]; self.assertLess(rec["FORCE_MAX"], r["counts_at_limit"]); self.assertLess(rec["FORCE_REL"], rec["FORCE_MAX"]); self.assertGreater(rec["FORCE_REL"], 0)
        self.assertGreaterEqual(r["hysteresis_counts"], 8)
    def test_margin_grows_with_noise_and_hysteresis(self):
        a = K.analyse(synth(self.loads, noise=1, hyst=0), 15.0)["recommended"]["FORCE_MAX"]; b = K.analyse(synth(self.loads, noise=8, hyst=30), 15.0)["recommended"]["FORCE_MAX"]
        self.assertLess(b, a)
    def test_known_exact_curve(self):
        rows = [(f"t{k}", "up", m, 2 * m) for m in (0, 100, 200, 300, 400, 500) for k in range(3)]
        r = K.analyse(rows, limit_n=2.0, margin_sigma=3.0)                  # 2 N = 203.9 g -> 407.9 counts, sigma 0 -> floor(407.9 - 0 - 0 - 1) = 406
        self.assertAlmostEqual(r["counts_at_limit"], 2 * 2.0 / 9.80665 * 1000, places=1); self.assertEqual(r["recommended"]["FORCE_MAX"], 406)
        self.assertEqual(r["recommended"]["FORCE_REL"], 406 - max(0, 0, 0.05 * 1000, 32))
    def test_refusals(self):
        bad = {"too_few_loads": synth([0, 100, 200], 5), "too_few_reps": synth(self.loads, 2), "limit_beyond_data": None, "non_monotonic": [(f"t{k}", "up", m, a) for k in range(3) for m, a in ((0, 10), (100, 500), (200, 300), (300, 900), (400, 1200), (500, 1500))]}
        self.assertRaises(K.CalError, K.analyse, bad["too_few_loads"], 5.0); self.assertRaises(K.CalError, K.analyse, bad["too_few_reps"], 5.0)
        self.assertRaises(K.CalError, K.analyse, synth(self.loads), 500.0); self.assertRaises(K.CalError, K.analyse, bad["non_monotonic"], 3.0)
    def test_saturation_and_missing_down_data_warn(self):
        r = K.analyse(synth(self.loads, gain=1.12, down=False), 20.0); text = " ".join(r["warnings"]); self.assertIn("rail", text); self.assertIn("no 'down' data", text)
    def test_loader_validation_and_cli(self):
        d = tempfile.mkdtemp(); p = os.path.join(d, "c.csv")
        def w(rows, header=("trial", "direction", "mass_g", "adc")):
            with open(p, "w", newline="") as fh: cw = csv.writer(fh); cw.writerow(header); cw.writerows(rows)
        w([("a", "up", 1, 1)], header=("t", "d", "m", "a")); self.assertRaises(K.CalError, K.load, p)
        w([("a", "sideways", 1, 1)]); self.assertRaises(K.CalError, K.load, p); w([("a", "up", 1, 5000)]); self.assertRaises(K.CalError, K.load, p); w([("a", "up", -1, 5)]); self.assertRaises(K.CalError, K.load, p)
        w(synth(self.loads, hyst=5)); out = os.path.join(d, "r.json"); self.assertEqual(K.main(["--data", p, "--limit-n", "15", "--out", out]), 0)
        with open(out) as fh: self.assertIn("FORCE_MAX", json.load(fh)["recommended"])
        self.assertEqual(K.main(["--data", p, "--limit-n", "5000", "--out", out]), 2)
        t = os.path.join(d, "t.csv"); self.assertEqual(K.main(["--make-template", t]), 0)
        with open(t) as fh: self.assertEqual(fh.read(), "trial,direction,mass_g,adc\n")

if __name__ == "__main__": unittest.main()
