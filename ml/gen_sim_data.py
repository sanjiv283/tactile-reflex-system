"""SIMULATED tactile dataset. Not real sensor data.
Each episode: no contact -> contact ramp -> plateau (light / normal / excessive) with noise and creep -> release.
Labels come from the scenario that generated the episode (stand-in for operator-labelled recordings).
Replace with real FSR recordings (same CSV columns) once collected."""
import numpy as np

CLASSES = ["no contact", "light contact", "normal grip", "excessive force"]
# plateau force ranges in ADC counts (SIMULATED); ranges deliberately overlap
RANGES = {1: (80, 650), 2: (500, 1900), 3: (1600, 3400)}

def episode(rng, n=400):
    f = np.zeros(n); y = np.zeros(n, int)
    t0 = rng.integers(30, 100)                  # contact onset
    cls = rng.choice([1, 2, 3], p=[0.3, 0.4, 0.3])
    level = rng.uniform(*RANGES[cls])
    ramp = rng.integers(8, 60)                  # stiffness: short ramp = stiff object
    hold = rng.integers(100, 220)
    t1 = min(t0 + ramp + hold, n - 40)
    for t in range(n):
        if t < t0: v = 0.0
        elif t < t0 + ramp: v = level * (t - t0 + 1) / ramp
        elif t < t1: v = level * (1 - 0.0004 * (t - t0 - ramp))        # slow creep
        else: v = level * max(0.0, 1 - (t - t1) / 25.0)                # release
        f[t] = v
    f = f * rng.normal(1.0, 0.03) + rng.normal(0, 8, n) + rng.normal(0, 3)  # gain error, noise, offset
    f = np.clip(f, 0, 4000)
    y[t0 + 5:t1] = cls                          # first 5 samples of onset left as 'no contact'
    return f, y

def features(f):
    n = len(f); X = np.zeros((n, 6)); dur = 0
    for t in range(n):
        dur = dur + 1 if f[t] > 40 else 0
        p2 = f[t - 2] if t >= 2 else 0.0
        p5 = f[t - 5] if t >= 5 else 0.0
        ma = f[max(0, t - 7):t + 1].mean()
        X[t] = [f[t], p2, f[t] - p5, ma, min(dur, 255), f[t] - f[t - 1] if t else 0.0]
    return X

FEATURES = ["force", "force_prev2", "delta5", "moving_avg8", "contact_duration", "delta1"]

def build(n_episodes=600, seed=0):
    rng = np.random.default_rng(seed)
    Xs, ys, gs, fs = [], [], [], []
    for e in range(n_episodes):
        f, y = episode(rng)
        Xs.append(features(f)); ys.append(y); gs.append(np.full(len(f), e)); fs.append(f)
    return np.vstack(Xs), np.concatenate(ys), np.concatenate(gs), np.concatenate(fs)
