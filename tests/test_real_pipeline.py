"""Real-data pipeline: runs end to end on a SIMULATED FIXTURE (clearly labelled) and rejects every kind of malformed recording."""
import csv, hashlib, json, os, shutil, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ml"))
import numpy as np
import real_data_pipeline as P
from gen_sim_data import episode
from tree_model import TreeModel

def write_session(path, f, y, rate=1000.0, t0=0.0, mutate=None):
    rows = [[round(t0 + i / rate, 6), round(float(v), 3), int(l)] for i, (v, l) in enumerate(zip(f, y))]
    if mutate: rows = mutate(rows)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["t_s", "adc", "label"]); w.writerows(rows)

class Pipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp(); rng = np.random.default_rng(11); cls.paths = []
        for k in range(12):                                 # each session = 2 episodes so every class is plentiful
            fs, ys = zip(*[episode(rng) for _ in range(2)]); p = os.path.join(cls.d, f"s{k:02d}.csv"); write_session(p, np.concatenate(fs), np.concatenate(ys)); cls.paths.append(p)
    @classmethod
    def tearDownClass(cls): shutil.rmtree(cls.d, ignore_errors=True)
    def out(self): return tempfile.mkdtemp(dir=self.d)
    def test_end_to_end_on_fixture(self):
        o = self.out(); r = P.run(self.paths, "SIMULATED_FIXTURE", o, min_per_class=100)
        self.assertEqual(r["data_source"], "SIMULATED_FIXTURE"); self.assertIn("SIMULATED FIXTURE", r["warning"]); self.assertGreater(r["accuracy"], 0.85)
        self.assertGreaterEqual(r["accuracy"], r["baseline_force_only_accuracy"] - 0.02)
        m = TreeModel.load(os.path.join(o, "tree.json")); self.assertIn(m.predict_one([100, 90, 5, 95, 3, 1]), (0, 1, 2, 3))
        self.assertEqual(r["inputs_sha256"][os.path.basename(self.paths[0])], P._sha(self.paths[0]))
    def test_never_overwrites_project_model(self):
        pj = os.path.join(ROOT, "results", "tree.json"); before = P._sha(pj); P.run(self.paths, "SIMULATED_FIXTURE", self.out(), min_per_class=100)
        self.assertEqual(P._sha(pj), before)
    def test_session_wise_split_has_no_overlap(self):
        r = P.run(self.paths, "SIMULATED_FIXTURE", self.out(), min_per_class=100); self.assertEqual(len(r["test_sessions"]), 3); self.assertEqual(r["test_sessions"], ["s09.csv", "s10.csv", "s11.csv"])
    def test_bad_source_label(self): self.assertRaises(P.DataError, P.run, self.paths, "maybe", self.out())
    def test_too_few_sessions(self): self.assertRaises(P.DataError, P.run, self.paths[:3], "REAL", self.out())
    def test_too_few_samples_per_class(self): self.assertRaises(P.DataError, P.run, self.paths, "REAL", self.out(), 1000.0, 10**7)
    def bad(self, name, mutate=None, header=None, rate=1000.0, f=None, rate_arg=1000.0):
        rng = np.random.default_rng(3); ff, yy = episode(rng); p = os.path.join(self.d, name + ".csv"); write_session(p, ff if f is None else f, yy, rate, mutate=mutate)
        if header:
            lines = open(p).read().split("\n"); lines[0] = header; open(p, "w").write("\n".join(lines))
        self.assertRaises(P.DataError, P.load_session, p, rate_arg)
    def test_malformed_inputs_are_rejected(self):
        self.bad("hdr", header="time,adc,label"); self.bad("adc_hi", mutate=lambda r: r[:10] + [[r[10][0], 5000, 1]] + r[11:])
        self.bad("adc_neg", mutate=lambda r: r[:10] + [[r[10][0], -1, 1]] + r[11:]); self.bad("label", mutate=lambda r: r[:10] + [[r[10][0], r[10][1], 7]] + r[11:])
        self.bad("nonmono", mutate=lambda r: r[:10] + [r[9]] + r[11:]); self.bad("nan", mutate=lambda r: r[:10] + [[r[10][0], "nan", 1]] + r[11:])
        self.bad("text", mutate=lambda r: r[:10] + [[r[10][0], "abc", 1]] + r[11:]); self.bad("rate", rate=100.0)
        self.bad("gap", mutate=lambda r: r[:100] + [[x[0] + 1.0, x[1], x[2]] for x in r[100:]]); self.bad("stuck", f=np.full(400, 123.0))
        self.bad("short", mutate=lambda r: r[:20])
    def test_empty_label_means_unlabelled(self):
        p = os.path.join(self.d, "unl.csv"); rng = np.random.default_rng(4); f, y = episode(rng)
        write_session(p, f, y, mutate=lambda r: [[a, b, "" if i % 2 else c] for i, (a, b, c) in enumerate(r)])
        a, l = P.load_session(p, 1000.0); self.assertEqual(int((l == -1).sum()), len(l) // 2)

if __name__ == "__main__": unittest.main()
