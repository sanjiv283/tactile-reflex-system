"""Plot RTL-simulation traces written by tb_top (results/trace_*.csv). Time axis assumes a 50 MHz clock."""
import pandas as pd
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

def plot(csv, out, title, event_col=None, xlim=None):
    d = pd.read_csv(csv); t = (d.cycle - d.cycle.iloc[0]) * 0.02   # us
    fig, ax = plt.subplots(4, 1, figsize=(9, 6.2), sharex=True)
    ax[0].step(t, d.force_code, color="#3D5A80", where="post"); ax[0].axhline(0xA00, color="#C8404F", ls="--", lw=1)
    ax[0].text(t.iloc[0], 0xA00 + 60, "FORCE_MAX", color="#C8404F", fontsize=9); ax[0].set_ylabel("force code")
    ax[1].step(t, d.ai_class, color="#5F7380", where="post"); ax[1].set_ylabel("AI class"); ax[1].set_yticks([0, 1, 2, 3])
    ax[2].step(t, d.safe_state, color="#C8404F", where="post"); ax[2].set_ylabel("safe_state"); ax[2].set_yticks([0, 1])
    ax[3].plot(t, d.pwm_out, color="#0E7C7B", lw=0.6); ax[3].set_ylabel("pwm_out"); ax[3].set_yticks([0, 1]); ax[3].set_xlabel("time (us), RTL simulation")
    if xlim: ax[3].set_xlim(*xlim)
    fig.suptitle(title); fig.tight_layout(); fig.savefig(out, dpi=160); plt.close(fig)

plot("results/trace_override.csv", "results/wave_override.png", "AI says normal grip, force exceeds FORCE_MAX: Governor overrides (RTL simulation)")
plot("results/trace_estop.csv", "results/wave_estop.png", "Emergency stop: PWM forced low (RTL simulation)")
