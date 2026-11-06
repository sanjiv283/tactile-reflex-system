"""Narration synthesis (espeak-ng via the espeakng-loader wheel), timeline construction, ambient music, final mix."""
import sys, json, wave, os, math
import numpy as np
from scipy import signal
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tts_espeak as T
import script as S
HERE = "/home/user/tactile-reflex-system/demo_video/"
SR, FPS = 48000, 30
LEAD, GAP, TAIL = 0.8, 0.42, 1.4

def synth_beat(sp):
    x, sr = T.synth(sp, voice=b"en-us", wpm=158, pitch=44, rng=45)
    x = signal.resample_poly(x, SR, sr).astype(np.float32)
    b, a = signal.butter(2, 90 / (SR / 2), "high"); x = signal.lfilter(b, a, x)
    x = np.tanh(1.6 * x) / np.tanh(1.6); x = x / (np.abs(x).max() + 1e-9) * 0.89
    n = int(0.008 * SR); x[:n] *= np.linspace(0, 1, n); x[-n:] *= np.linspace(1, 0, n)
    return x.astype(np.float32)

def build():
    os.makedirs(HERE + "audio/narration", exist_ok=True)
    timeline, g = [], 0.0
    for si, sc in enumerate(S.SCENES):
        t = LEAD; beats = []
        for bi, (cap, ov) in enumerate(sc["beats"]):
            sp = S.speech(cap, ov); x = synth_beat(sp)
            fn = HERE + f"audio/narration/{sc['id']}_{bi + 1:02d}.wav"
            with wave.open(fn, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
            dur = len(x) / SR; beats.append(dict(cap=cap, speech=sp, t0=round(t, 3), t1=round(t + dur, 3), file=fn)); t += dur + GAP
        end = t - GAP + (TAIL if si < len(S.SCENES) - 1 else 5.6)
        frames = math.ceil(end * FPS); dur = frames / FPS
        timeline.append(dict(id=sc["id"], title=sc["title"], num=si + 1, start=round(g, 4), dur=round(dur, 4), frames=frames, beats=beats)); g += dur
    json.dump(dict(total=round(g, 4), fps=FPS, scenes=timeline), open(HERE + "audio/timeline.json", "w"), indent=1)
    return timeline, g

if __name__ == "__main__":
    tl, total = build()
    print(f"total {total:.1f}s = {int(total // 60)}:{total % 60:04.1f}")
    for s in tl: print(s["id"], f"start {s['start']:.1f}s dur {s['dur']:.1f}s beats {len(s['beats'])}", "last beat ends", s["beats"][-1]["t1"])
