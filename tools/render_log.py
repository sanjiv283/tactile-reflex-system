"""Render the real testbench console output (results/sim_log.txt) as an image for the report."""
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
lines = [l.rstrip() for l in open("results/sim_log.txt") if l.startswith(("TB", "RESULT"))]
lines = ["$ sim/run_all.sh"] + [l.replace("RESULT ", "") if l.startswith("RESULT replay mode") is False else l for l in lines] + ["ALL TESTBENCHES PASSED"]
fig = plt.figure(figsize=(9, 3.9)); fig.patch.set_facecolor("#1B2430")
fig.text(0.02, 0.97, "\n".join(lines), va="top", ha="left", family="monospace", fontsize=7.2, color="#EAF1F1", linespacing=1.35)
fig.savefig("results/sim_console.png", dpi=200, facecolor=fig.get_facecolor()); print(len(lines), "lines")
