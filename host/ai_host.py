"""Laptop side of the AI path (DE2-115 RS-232 port, 115200 8N1).
FPGA -> laptop: 3-byte telemetry  0x5A, {safe, sensor_fault, estop, ai_valid, force[11:8]}, force[7:0]   (about 1 kHz)
laptop -> FPGA: 3-byte AI packet   0xA5, DATA, ~DATA   with DATA = {000, valid, ~class[1:0], class[1:0]}
The FPGA treats this as advice only: it is ignored if invalid, stale (no packet for 10 ms) or when a hard limit trips.

  python3 host/ai_host.py --selftest            # no hardware needed
  python3 host/ai_host.py --port COM3 --log run.csv [--no-ai]   # needs pyserial
"""
import argparse, csv, os, pickle, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ml"))

def build_ai_packet(cls, valid=True):
    d = (int(valid) << 4) | ((~cls & 3) << 2) | (cls & 3)
    return bytes([0xA5, d, (~d) & 0xFF])

def parse_telemetry(b):
    assert len(b) == 3 and b[0] == 0x5A
    return ((b[1] & 0x0F) << 8) | b[2], dict(safe=bool(b[1] & 0x80), sensor_fault=bool(b[1] & 0x40), estop=bool(b[1] & 0x20), ai_valid=bool(b[1] & 0x10))

class FeatureStream:
    """Causal features, identical to ml/gen_sim_data.features (checked by --selftest)."""
    def __init__(self): self.f = []; self.dur = 0
    def push(self, x):
        self.f.append(float(x)); f = self.f; t = len(f) - 1
        self.dur = self.dur + 1 if x > 40 else 0
        p2 = f[t - 2] if t >= 2 else 0.0
        p5 = f[t - 5] if t >= 5 else 0.0
        return [f[t], p2, f[t] - p5, sum(f[max(0, t - 7):t + 1]) / len(f[max(0, t - 7):t + 1]), min(self.dur, 255), f[t] - f[t - 1] if t else 0.0]

def selftest():
    import numpy as np
    from gen_sim_data import episode, features
    assert build_ai_packet(2) == bytes([0xA5, 0x16, 0xE9]) and build_ai_packet(3) == bytes([0xA5, 0x13, 0xEC])
    assert build_ai_packet(0) == bytes([0xA5, 0x1C, 0xE3]) and build_ai_packet(1) == bytes([0xA5, 0x19, 0xE6])
    assert parse_telemetry(bytes([0x5A, 0x95, 0x40])) == (0x540, dict(safe=True, sensor_fault=False, estop=False, ai_valid=True))
    f, _ = episode(np.random.default_rng(7)); X = features(f); fs = FeatureStream()
    S = np.array([fs.push(v) for v in f]); assert np.allclose(S, X), "streaming features differ from training features"
    clf = pickle.load(open(os.path.join(os.path.dirname(__file__), "..", "results", "tree.pkl"), "rb"))
    assert (clf.predict(S) == clf.predict(X)).all()
    print("selftest ok: packet format, telemetry parsing, streaming features == training features")

def run(port, log, use_ai):
    import serial
    clf = pickle.load(open(os.path.join(os.path.dirname(__file__), "..", "results", "tree.pkl"), "rb"))
    ser = serial.Serial(port, 115200, timeout=0.1); fs = FeatureStream(); t0 = time.perf_counter()
    out = csv.writer(open(log, "w", newline="")) if log else None
    if out: out.writerow(["t_s", "force", "safe", "sensor_fault", "estop", "ai_valid", "ai_class", "inference_us"])
    buf = bytearray()
    while True:
        buf += ser.read(64)
        while len(buf) >= 3:
            if buf[0] != 0x5A: buf.pop(0); continue
            force, fl = parse_telemetry(bytes(buf[:3])); del buf[:3]
            cls, us = 0, 0.0
            if use_ai:
                x = fs.push(force); a = time.perf_counter_ns(); cls = int(clf.predict([x])[0]); us = (time.perf_counter_ns() - a) / 1e3
                ser.write(build_ai_packet(cls))
            if out: out.writerow([round(time.perf_counter() - t0, 4), force, fl["safe"], fl["sensor_fault"], fl["estop"], fl["ai_valid"], cls, round(us, 1)])

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--selftest", action="store_true"); ap.add_argument("--port"); ap.add_argument("--log"); ap.add_argument("--no-ai", action="store_true")
    a = ap.parse_args()
    if a.selftest: selftest()
    elif a.port: run(a.port, a.log, not a.no_ai)
    else: ap.print_help()
