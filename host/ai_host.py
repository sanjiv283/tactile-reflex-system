"""Laptop side of the AI path (DE2-115 RS-232 port, 115200 8N1).
FPGA -> laptop: 3-byte telemetry  0x5A, {safe, sensor_fault, estop, ai_valid, force[11:8]}, force[7:0]   (about 1 kHz)
laptop -> FPGA: 3-byte AI packet   0xA5, DATA, ~DATA   with DATA = {000, valid, ~class[1:0], class[1:0]}
The FPGA treats this as advice only: it is ignored if invalid, stale (no packet for 10 ms) or when a hard limit trips.
The host is NOT in the safety path: a crash, a stall or a wrong answer here can only lose the AI advice.

  python3 host/ai_host.py --selftest                              # no hardware needed
  python3 host/ai_host.py --port COM3 --log run.csv [--no-ai] [--max-seconds N] [--model results/tree.json]   # needs pyserial

The model is results/tree.json (plain JSON, evaluated by ml/tree_model.py). No serialised Python objects are ever loaded.
"""
import argparse, csv, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ml"))
from tree_model import TreeModel

HEADER_TLM, HEADER_AI = 0x5A, 0xA5
DEFAULT_MODEL = os.path.join(HERE, "..", "results", "tree.json")

def build_ai_packet(cls, valid=True):
    if cls not in (0, 1, 2, 3): raise ValueError(f"AI class must be 0..3, got {cls!r}")
    d = (int(bool(valid)) << 4) | ((~cls & 3) << 2) | (cls & 3)
    return bytes([HEADER_AI, d, (~d) & 0xFF])

def parse_telemetry(b):
    """-> (force, flags) or None when b is not a well-formed 3-byte telemetry frame."""
    if len(b) != 3 or b[0] != HEADER_TLM: return None
    return ((b[1] & 0x0F) << 8) | b[2], dict(safe=bool(b[1] & 0x80), sensor_fault=bool(b[1] & 0x40), estop=bool(b[1] & 0x20), ai_valid=bool(b[1] & 0x10))

class TelemetryParser:
    """Byte stream -> frames. The protocol has no checksum, and 0x5A can legitimately appear inside a frame, so a frame is accepted only
    when the byte that follows it is again 0x5A (the stream is continuous, ~1 kHz). Costs one frame (about 1 ms) of latency and makes
    a false lock on a payload byte vanishingly unlikely. Everything else is dropped one byte at a time and counted."""
    def __init__(self): self.buf = bytearray(); self.frames = 0; self.dropped = 0
    def feed(self, data):
        self.buf += data; out = []
        while True:
            while self.buf and self.buf[0] != HEADER_TLM: self.buf.pop(0); self.dropped += 1
            if len(self.buf) < 4: break                     # need the next header to confirm alignment
            if self.buf[3] == HEADER_TLM:
                out.append(parse_telemetry(bytes(self.buf[:3]))); del self.buf[:3]; self.frames += 1
            else: self.buf.pop(0); self.dropped += 1        # false header: slide by one byte and re-check
        return out

class FeatureStream:
    """Causal features, identical to ml/gen_sim_data.features (checked by --selftest)."""
    def __init__(self): self.f = []; self.dur = 0
    def push(self, x):
        self.f.append(float(x)); f = self.f; t = len(f) - 1
        self.dur = self.dur + 1 if x > 40 else 0
        p2 = f[t - 2] if t >= 2 else 0.0
        p5 = f[t - 5] if t >= 5 else 0.0
        return [f[t], p2, f[t] - p5, sum(f[max(0, t - 7):t + 1]) / len(f[max(0, t - 7):t + 1]), min(self.dur, 255), f[t] - f[t - 1] if t else 0.0]

LOG_HEADER = ["t_s", "force", "safe", "sensor_fault", "estop", "ai_valid", "ai_class", "inference_us"]

class HostSession:
    """One connection. `ser` is anything with read(n) -> bytes and write(bytes) (pyserial.Serial or a test double)."""
    def __init__(self, ser, model, writer=None, use_ai=True, clock=time.perf_counter, stale_s=0.5):
        self.ser, self.model, self.writer, self.use_ai, self.clock, self.stale_s = ser, model, writer, use_ai, clock, stale_s
        self.parser, self.fs = TelemetryParser(), FeatureStream()
        self.t0 = clock(); self.last_rx = self.t0; self.stale = False
        self.packets_sent = 0; self.frames = 0
    def poll(self):
        """Read once, handle every complete frame. Returns the number of frames handled."""
        data = self.ser.read(64)
        now = self.clock()
        if data: self.last_rx = now; self.stale = False
        elif now - self.last_rx > self.stale_s: self.stale = True       # no telemetry: stop advising (the FPGA would ignore it anyway)
        n = 0
        for force, fl in self.parser.feed(data):
            cls, us = 0, 0.0
            x = self.fs.push(force)
            if self.use_ai:
                a = time.perf_counter_ns(); cls = int(self.model.predict_one(x)); us = (time.perf_counter_ns() - a) / 1e3
                self.ser.write(build_ai_packet(cls)); self.packets_sent += 1
            if self.writer: self.writer.writerow([round(self.clock() - self.t0, 4), force, fl["safe"], fl["sensor_fault"], fl["estop"], fl["ai_valid"], cls, round(us, 1)])
            n += 1
        self.frames += n
        return n

def run(port, log, use_ai, model_path=DEFAULT_MODEL, max_seconds=None, retries=5, opener=None, sleep=time.sleep):
    """Returns 0 on a clean stop, 2 when the port could not be (re)opened. Ctrl-C stops cleanly and always closes the log."""
    import serial
    model = TreeModel.load(model_path)
    opener = opener or (lambda: serial.Serial(port, 115200, timeout=0.1))
    fh = open(log, "w", newline="") if log else None
    try:
        writer = csv.writer(fh) if fh else None
        if writer: writer.writerow(LOG_HEADER)
        attempts = 0; t_end = None if max_seconds is None else time.perf_counter() + max_seconds
        while True:
            try: ser = opener()
            except Exception as e:
                attempts += 1; print(f"cannot open {port}: {e} (attempt {attempts}/{retries})", file=sys.stderr)
                if attempts >= retries: return 2
                sleep(min(2 ** attempts, 10)); continue
            sess = HostSession(ser, model, writer, use_ai)
            try:
                while t_end is None or time.perf_counter() < t_end:
                    sess.poll()
                    if fh and sess.frames % 200 == 0: fh.flush()
                return 0
            except KeyboardInterrupt: return 0
            except (OSError, getattr(serial, "SerialException", OSError)) as e:
                print(f"serial error: {e}; reconnecting", file=sys.stderr)
                if sess.frames: attempts = 0                  # it had been working: start the retry budget afresh
            finally:
                try: ser.close()
                except Exception: pass
            attempts += 1
            if attempts >= retries: return 2
            sleep(1)
    finally:
        if fh: fh.close()

def selftest():
    import numpy as np
    from gen_sim_data import episode, features
    assert build_ai_packet(2) == bytes([0xA5, 0x16, 0xE9]) and build_ai_packet(3) == bytes([0xA5, 0x13, 0xEC])
    assert build_ai_packet(0) == bytes([0xA5, 0x1C, 0xE3]) and build_ai_packet(1) == bytes([0xA5, 0x19, 0xE6])
    assert parse_telemetry(bytes([0x5A, 0x95, 0x40])) == (0x540, dict(safe=True, sensor_fault=False, estop=False, ai_valid=True))
    f, _ = episode(np.random.default_rng(7)); X = features(f); fs = FeatureStream()
    S = np.array([fs.push(v) for v in f]); assert np.allclose(S, X), "streaming features differ from training features"
    m = TreeModel.load(DEFAULT_MODEL)
    assert m.predict(S.tolist()) == m.predict(X.tolist())
    print("selftest ok: packet format, telemetry parsing, streaming features == training features, JSON model")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true"); ap.add_argument("--port"); ap.add_argument("--log"); ap.add_argument("--no-ai", action="store_true")
    ap.add_argument("--model", default=DEFAULT_MODEL); ap.add_argument("--max-seconds", type=float)
    a = ap.parse_args()
    if a.selftest: selftest()
    elif a.port: sys.exit(run(a.port, a.log, not a.no_ai, a.model, a.max_seconds))
    else: ap.print_help()
