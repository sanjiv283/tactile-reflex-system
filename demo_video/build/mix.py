"""Synthesize an ambient music bed (numpy), place narration at timeline positions, duck music under speech, write demo_video/audio/mix.wav."""
import json, wave, numpy as np, os
from scipy import signal
HERE = "/home/user/tactile-reflex-system/demo_video/"
SR = 48000
TL = json.load(open(HERE + "audio/timeline.json")); TOTAL = TL["total"]; N = int((TOTAL + 1.0) * SR)
rng = np.random.default_rng(7)

def tone(f, t, harm=(1, .5, .25, .12)):
    return sum(a * np.sin(2 * np.pi * f * (h + 1) * t + rng.uniform(0, 6.28)) * (1.0 if h == 0 else 1.0) for h, a in enumerate(harm) if f * (h + 1) < 3500)
CH = [(110.00, [55.0, 110.0, 164.81, 220.0, 261.63, 329.63]), (87.31, [43.65, 87.31, 130.81, 174.61, 220.0, 261.63]), (130.81, [65.41, 130.81, 196.0, 261.63, 329.63]), (98.0, [49.0, 98.0, 146.83, 196.0, 246.94, 293.66])]
BEAT = 60 / 72; CHORD = 8 * BEAT
t_all = np.arange(N) / SR
pad = np.zeros(N, np.float32); arp = np.zeros(N, np.float32)
n_ch = int(np.ceil((N / SR) / CHORD)) + 1
for k in range(n_ch):
    root, notes = CH[k % 4]; s0 = k * CHORD - 1.6; s1 = (k + 1) * CHORD + 1.6
    i0, i1 = max(0, int(s0 * SR)), min(N, int(s1 * SR))
    if i1 <= i0: continue
    t = t_all[i0:i1]; env = np.clip((t - s0) / 1.6, 0, 1) * np.clip((s1 - t) / 1.6, 0, 1); env = env * env * (3 - 2 * env)
    seg = sum(tone(f, t) * (0.9 if f < 70 else 0.55) for f in notes) / len(notes)
    seg += 0.5 * np.sin(2 * np.pi * root / 2 * t) * 0.6
    pad[i0:i1] += (seg * env).astype(np.float32)
    # faint arpeggio: 8th notes
    tones = [f * 2 for f in notes[1:5]]; pat = [0, 2, 1, 3, 2, 1, 3, 2]
    for j in range(16):
        ts = k * CHORD + j * BEAT / 2; i = int(ts * SR)
        if i >= N or i < 0: continue
        f = tones[pat[j % 8] % len(tones)] * (2 if j % 4 == 3 else 1)
        m = min(int(0.9 * SR), N - i); tt = np.arange(m) / SR; arp[i:i + m] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)) * np.exp(-tt * 5.5) * 0.5
# slow movement + low-pass
lfo = 0.85 + 0.15 * np.sin(2 * np.pi * 0.07 * t_all); pad *= lfo
b, a = signal.butter(2, 2400 / (SR / 2), "low"); pad = signal.lfilter(b, a, pad).astype(np.float32)
# arpeggio level follows scene energy (quieter under dense information scenes)
lvl = np.zeros(N, np.float32)
for sc in TL["scenes"]:
    g = {1: .9, 2: .35, 3: .7, 4: .3, 5: .3, 6: .35, 7: .8, 8: 1.0}[sc["num"]]
    lvl[int(sc["start"] * SR):int((sc["start"] + sc["dur"]) * SR)] = g
lvl = signal.lfilter(*signal.butter(1, 0.4 / (SR / 2)), lvl).astype(np.float32)
bed = pad * 1.0 + arp * 0.16 * lvl
# reverb
ir_n = int(2.4 * SR); ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR * 2.6); ir[:int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR)); ir /= np.sqrt((ir ** 2).sum())
wet = signal.fftconvolve(bed, ir, mode="full")[:N].astype(np.float32)
bed = (0.62 * bed + 0.55 * wet).astype(np.float32)
# stereo width: tiny delay between channels
L = bed; R = np.concatenate([np.zeros(int(0.011 * SR), np.float32), bed[:-int(0.011 * SR)]]) * 0.97
music = np.stack([L, R]); music /= (np.sqrt((music ** 2).mean()) + 1e-9); music *= 10 ** (-26 / 20)
# fade in/out
fi, fo = int(2.5 * SR), int(4.0 * SR); music[:, :fi] *= np.linspace(0, 1, fi); end = int(TOTAL * SR); music[:, end - fo:end] *= np.linspace(1, 0, fo); music[:, end:] = 0
# narration
nar = np.zeros(N, np.float32)
for sc in TL["scenes"]:
    for b_ in sc["beats"]:
        with wave.open(b_["file"]) as w: x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        i = int((sc["start"] + b_["t0"]) * SR); nar[i:i + len(x)] += x
# ducking
env = np.abs(nar); env = signal.lfilter(*signal.butter(2, 6 / (SR / 2)), env); env = np.clip(env / 0.18, 0, 1)
duck = 1 - 0.62 * signal.lfilter(*signal.butter(1, 3 / (SR / 2)), env).clip(0, 1)
out = np.stack([nar, nar]) * 0.95 + music * duck[None, :] * 1.0
peak = np.abs(out).max(); out = np.tanh(out * 1.1) / np.tanh(1.1) if peak > 0.98 else out
out = out[:, :int(TOTAL * SR)]
pcm = (np.clip(out, -1, 1).T * 32767).astype(np.int16)
with wave.open(HERE + "audio/mix.wav", "wb") as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print("mix seconds", round(pcm.shape[0] / SR, 2), "narration peak", float(np.abs(nar).max()), "mix peak", float(np.abs(out).max()), "music rms dBFS", round(20 * np.log10(np.sqrt((music ** 2).mean())), 1))
