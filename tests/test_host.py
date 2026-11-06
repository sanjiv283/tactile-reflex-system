"""Host software tests with a mock serial port (no hardware, no pyserial needed) and the JSON model format."""
import csv, io, itertools, json, os, sys, tempfile, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "host")); sys.path.insert(0, os.path.join(ROOT, "ml"))
import ai_host as H
from tree_model import TreeModel, FORMAT

def frame(force, safe=False, sf=False, es=False, av=False):
    return bytes([0x5A, (safe << 7) | (sf << 6) | (es << 5) | (av << 4) | (force >> 8), force & 0xFF])

class MockSerial:
    """Scripted read() chunks; records writes; can raise on demand."""
    def __init__(self, chunks, raise_after=None): self.chunks, self.writes, self.n, self.raise_after, self.closed = list(chunks), [], 0, raise_after, False
    def read(self, n):
        self.n += 1
        if self.raise_after is not None and self.n > self.raise_after: raise OSError("device unplugged")
        return self.chunks.pop(0) if self.chunks else b""
    def write(self, b): self.writes.append(bytes(b))
    def close(self): self.closed = True

class ConstModel:
    def __init__(self, c): self.c = c
    def predict_one(self, x): return self.c

class Packets(unittest.TestCase):
    def test_packet_format_and_complement(self):
        for cls, valid in itertools.product(range(4), (True, False)):
            p = H.build_ai_packet(cls, valid)
            self.assertEqual((p[0], len(p)), (0xA5, 3)); self.assertEqual(p[2], (~p[1]) & 0xFF)
            self.assertEqual(p[1] & 3, cls); self.assertEqual((p[1] >> 2) & 3, (~cls) & 3); self.assertEqual((p[1] >> 4) & 1, int(valid))
    def test_bad_class_rejected(self):
        for bad in (-1, 4, 7, None, "2"): self.assertRaises(ValueError, H.build_ai_packet, bad)
    def test_telemetry_roundtrip_exhaustive(self):
        for force in range(4096):
            for fl in range(16):
                f, d = H.parse_telemetry(frame(force, bool(fl & 8), bool(fl & 4), bool(fl & 2), bool(fl & 1)))
                self.assertEqual((f, d["safe"], d["sensor_fault"], d["estop"], d["ai_valid"]), (force, bool(fl & 8), bool(fl & 4), bool(fl & 2), bool(fl & 1)))
    def test_malformed_telemetry_returns_none(self):
        for b in (b"", b"\x5a", b"\x5a\x00", b"\x00\x00\x00", b"\x5a\x00\x00\x00"): self.assertIsNone(H.parse_telemetry(b))

class Parser(unittest.TestCase):
    def stream(self, forces): return b"".join(frame(f) for f in forces)
    def test_clean_stream_and_every_split_point(self):
        forces = [100, 0x5A, 0x15A, 4095, 0, 0x5A5, 7, 8]; data = self.stream(forces) + frame(1)    # trailing frame confirms the last one
        for cut in range(len(data) + 1):
            p = TelemetryParser = H.TelemetryParser(); got = p.feed(data[:cut]) + p.feed(data[cut:])
            self.assertEqual([g[0] for g in got], forces, f"split at {cut}"); self.assertEqual(p.dropped, 0)
    def test_byte_at_a_time(self):
        p = H.TelemetryParser(); got = []
        for b in self.stream([5, 6, 0x5A, 8, 9]) + frame(0): got += p.feed(bytes([b]))
        self.assertEqual([g[0] for g in got], [5, 6, 0x5A, 8, 9])
    def test_garbage_prefix_resyncs(self):
        p = H.TelemetryParser(); got = p.feed(b"\x11\x22\x33\x44" + self.stream([10, 11, 12]) + frame(0))
        self.assertEqual([g[0] for g in got], [10, 11, 12]); self.assertEqual(p.dropped, 4)
    def test_dropped_byte_loses_at_most_two_frames_then_recovers(self):
        forces = list(range(1, 21)); data = bytearray(self.stream(forces)); del data[3 * 5 + 1]   # drop one byte inside frame #6
        p = H.TelemetryParser(); got = [g[0] for g in p.feed(bytes(data) + frame(0))]
        self.assertLessEqual(len(forces) - len(got), 2); self.assertEqual(got[-5:], forces[-5:]); self.assertTrue(set(got) <= set(forces))
    def test_payload_0x5a_does_not_misframe(self):
        # force low byte 0x5A and flags byte 0x5A: header-lookalikes inside a frame must not shift the alignment
        forces = [0x05A, 0x25A, 0x45A, 0x55A, 0x65A, 0x75A]; p = H.TelemetryParser()
        got = [g[0] for g in p.feed(self.stream(forces) + frame(0))]; self.assertEqual(got, forces)
    def test_long_random_noise_never_crashes(self):
        import random; r = random.Random(5); p = H.TelemetryParser()
        for _ in range(2000): p.feed(bytes(r.randrange(256) for _ in range(r.randrange(1, 40))))

class Session(unittest.TestCase):
    def run_session(self, chunks, model=None, use_ai=True, **kw):
        out = io.StringIO(); w = csv.writer(out); ser = MockSerial(chunks)
        s = H.HostSession(ser, model or ConstModel(2), w, use_ai, **kw)
        for _ in range(len(chunks) + 1): s.poll()
        return s, ser, out.getvalue()
    def test_one_packet_per_telemetry_frame_with_model_class(self):
        s, ser, log = self.run_session([frame(100) * 1 + frame(200) + frame(300) + frame(0)])
        self.assertEqual(ser.writes, [H.build_ai_packet(2)] * 3); self.assertEqual(s.packets_sent, 3)
        rows = list(csv.reader(io.StringIO(log))); self.assertEqual([r[1] for r in rows], ["100", "200", "300"])
    def test_no_ai_mode_never_writes(self):
        s, ser, log = self.run_session([frame(100) + frame(200) + frame(0)], use_ai=False)
        self.assertEqual(ser.writes, []); self.assertEqual(len(list(csv.reader(io.StringIO(log)))), 2)
    def test_safe_state_flags_are_logged_and_ai_still_only_advice(self):
        s, ser, log = self.run_session([frame(3000, safe=True, es=True) + frame(1, sf=True) + frame(0)])
        rows = list(csv.reader(io.StringIO(log))); self.assertEqual((rows[0][2], rows[0][4]), ("True", "True")); self.assertEqual(rows[1][3], "True")
    def test_stale_detection_and_recovery(self):
        t = [0.0]; ser = MockSerial([frame(1) + frame(2) + frame(0)]); s = H.HostSession(ser, ConstModel(0), None, True, clock=lambda: t[0], stale_s=0.5)
        s.poll(); self.assertFalse(s.stale); t[0] = 0.4; s.poll(); self.assertFalse(s.stale)
        t[0] = 0.6; s.poll(); self.assertTrue(s.stale)
        ser.chunks.append(frame(5) + frame(0)); t[0] = 0.7; s.poll(); self.assertFalse(s.stale)
    def test_real_model_class_is_in_range(self):
        m = TreeModel.load(os.path.join(ROOT, "results", "tree.json"))
        for f in (0, 50, 500, 2000, 2600, 4095): self.assertIn(m.predict_one(H.FeatureStream().push(f)), (0, 1, 2, 3))

class RunLoop(unittest.TestCase):
    def setUp(self): self.d = tempfile.mkdtemp()
    def test_serial_error_reconnects_then_gives_up_and_closes_log_and_port(self):
        sers = []
        def opener():
            s = MockSerial([], raise_after=0); sers.append(s); return s
        log = os.path.join(self.d, "r.csv")
        import types; sys.modules.setdefault("serial", types.SimpleNamespace(Serial=None, SerialException=OSError))
        rc = H.run("X", log, True, os.path.join(ROOT, "results", "tree.json"), retries=3, opener=opener, sleep=lambda s: None)
        self.assertEqual(rc, 2); self.assertTrue(all(s.closed for s in sers)); self.assertEqual(len(sers), 3)
        self.assertTrue(open(log).read().startswith("t_s,force"))
    def test_working_connection_gets_fresh_retry_budget(self):
        import types; sys.modules.setdefault("serial", types.SimpleNamespace(Serial=None, SerialException=OSError))
        sers = []
        def opener():
            good = len(sers) < 2       # two connections that deliver data and then drop, then only failures
            s = MockSerial([frame(10) + frame(11) + frame(0)] if good else [], raise_after=1 if good else 0); sers.append(s); return s
        rc = H.run("X", None, True, os.path.join(ROOT, "results", "tree.json"), retries=3, opener=opener, sleep=lambda s: None)
        self.assertEqual(rc, 2); self.assertEqual(len(sers), 4)   # without the reset it would give up after 3 connections
    def test_cannot_open_port_returns_error_code(self):
        import types; sys.modules.setdefault("serial", types.SimpleNamespace(Serial=None, SerialException=OSError))
        def opener(): raise OSError("no such port")
        self.assertEqual(H.run("X", None, True, os.path.join(ROOT, "results", "tree.json"), retries=2, opener=opener, sleep=lambda s: None), 2)
    def test_max_seconds_stops_cleanly(self):
        import types; sys.modules.setdefault("serial", types.SimpleNamespace(Serial=None, SerialException=OSError))
        self.assertEqual(H.run("X", None, False, os.path.join(ROOT, "results", "tree.json"), max_seconds=0.05, opener=lambda: MockSerial([]), sleep=lambda s: None), 0)

class Model(unittest.TestCase):
    base = dict(format=FORMAT, features=["a", "b"], classes=[0, 1], left=[1, -1, -1], right=[2, -1, -1], feature=[0, -2, -2], threshold=[5.0, -2.0, -2.0], leaf_class=[0, 0, 1])
    def test_tiny_tree(self):
        m = TreeModel(dict(self.base)); self.assertEqual((m.predict_one([5, 0]), m.predict_one([5.0001, 0])), (0, 1))
    def test_float32_semantics_like_sklearn(self):
        d = dict(self.base); d["threshold"] = [0.1, -2.0, -2.0]; m = TreeModel(d)       # float32(0.1) = 0.10000000149 > 0.1 (float64)
        self.assertEqual(m.predict_one([0.1, 0]), 1)
    def test_rejects_bad_models(self):
        bad = []
        d = dict(self.base); d["format"] = "pickle"; bad.append(d)
        d = dict(self.base); d["right"] = [2, -1]; bad.append(d)
        d = dict(self.base); d["left"] = [0, -1, -1]; bad.append(d)                    # self-loop
        d = dict(self.base); d["feature"] = [9, -2, -2]; bad.append(d)
        d = dict(self.base); d["left"] = [1, -1, -1]; d["right"] = [1, 0, -1]; bad.append(d)   # leaf with a child
        bad += [None, [], "x"]
        for b in bad: self.assertRaises((ValueError, KeyError, TypeError), TreeModel, b)
    def test_wrong_feature_count(self): self.assertRaises(ValueError, TreeModel(dict(self.base)).predict_one, [1])
    def test_matches_sklearn_if_available(self):
        try: import numpy as np, pickle
        except ImportError: self.skipTest("numpy missing")
        pk = os.path.join(ROOT, "results", "tree.pkl")
        if not os.path.exists(pk): self.skipTest("no legacy pickle to compare with")
        from gen_sim_data import build
        X, *_ = build(); m = TreeModel.load(os.path.join(ROOT, "results", "tree.json"))
        clf = pickle.load(open(pk, "rb")); self.assertTrue((np.array(m.predict(X.tolist())) == clf.predict(X)).all())
    def test_no_pickle_in_runtime_code(self):
        for f in ("host/ai_host.py", "ml/tree_model.py", "ml/train_eval.py"): self.assertIsNone(__import__("re").search(r"import\s+pickle|pickle\.(load|dump)|from\s+pickle", open(os.path.join(ROOT, f)).read()), f)

if __name__ == "__main__": unittest.main()
