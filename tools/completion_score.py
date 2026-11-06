#!/usr/bin/env python3
"""Weighted completion accounting. Each feature is scored 0..1 on five dimensions; the percentage of a dimension is the weighted mean.
  written   : the code/document exists
  implemented: it does what it is meant to do (in simulation / on the host); 0 when the thing cannot be run at all here
  tested    : automated tests of it exist and pass
  verified  : evidence BEYOND the author's own directed tests (audited mutation score, invariant monitor, bounded formal, byte-exact reproduction, co-simulation).
              STRICT: all of it was produced inside this project with its own tools and no third-party review, so the cap is 0.75, reached only where several kinds converge;
              one kind of evidence = 0.5, a single weak one = 0.25. Nothing here has been reviewed by anyone outside the project.
  hardware  : demonstrated on real hardware.  0 everywhere: no hardware was run.
Scores are judgements, listed here so they can be challenged; partial credit is deliberately conservative. Writes results/completion_score.json, prints a table."""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# id, name, weight, written, implemented, tested, verified, hardware, note
F = [
 ("adc_interface", "ADC SPI interface", 5, 1, 1, 1, 0.25, 0, "M18, frame-level validation"),
 ("conditioning", "Input conditioning / rail detection", 3, 1, 1, 1, 0.4, 0, "M17 now seen by two testbenches"),
 ("lut", "Force LUT", 3, 1, 1, 1, 0.25, 0, "M21, artifact reproduction"),
 ("governor", "Hard force limit + hysteresis + AI cap", 8, 1, 1, 1, 0.75, 0, "mutants, monitor S1-S5, formal P1-P5,P7-P8"),
 ("predictor", "Slope predictor", 4, 1, 1, 1, 0.25, 0, "M07, M12; formal only with a 3-clock window"),
 ("pwm", "PWM generator + kill", 4, 1, 1, 1, 0.75, 0, "M13, M42, M48, M49; monitor S2; formal W1-W6 proven for every counter value"),
 ("fault", "Fault handler (e-stop, sensor, watchdog)", 7, 1, 1, 1, 0.5, 0, "mutants, S3; formal treats its outputs as inputs"),
 ("ai_if", "AI control interface", 4, 1, 1, 1, 0.75, 0, "adversarial replay, M19, M20, M45, P5"),
 ("uart", "UART rx/tx/bridge", 5, 1, 1, 1, 0.5, 0, "49-vector framing test, 8 UART mutants, host_link; no real line"),
 ("telemetry", "Telemetry transmitter", 2, 1, 1, 1, 0.5, 0, "M25 killed by a unit testbench, the board testbench and the co-simulation"),
 ("reset_inputs", "Reset sync, debounce, input synchronisers", 5, 1, 0.75, 1, 0.4, 0, "M36-M41; CDC check over every boundary input; MISO structure unresolved (H-16): implemented only partly credited"),
 ("board_top", "Board wrapper (de2_115_top)", 4, 1, 1, 1, 0.35, 0, "M26, M38-M40 (M40 now two testbenches); debounce simulated at 32 clocks only"),
 ("pins", "DE2-115 pin assignments", 4, .5, 0, .5, 0, 0, "24 of 41 bits unassigned, none verified (checker + tests exist)"),
 ("sdc", "Timing constraints", 2, .5, 0, 0, 0, 0, "minimal SDC, no timing report"),
 ("host", "Host software (parser, session, reconnect)", 4, 1, 1, 1, 0.5, 0, "mock-serial tests; co-simulation with a reference model, six host behaviours and negative controls"),
 ("ml_sim", "ML model, JSON format, validation (simulated data)", 3, 1, 1, 1, 0.5, 0, "grouped CV, shuffle control, byte-exact reproduction"),
 ("ml_real", "Real-data ML pipeline", 3, 1, .5, 1, 0, 0, "runs only on a simulated fixture; no real recordings"),
 ("regression", "Regression runner and manifest", 3, 1, 1, 1, 0.5, 0, "negative tests of the runner itself"),
 ("mutation", "Mutation framework + audit", 3, 1, 1, 1, 0.4, 0, "49 mutants; kills with one assertion addressed and audited; hand-written mutants only"),
 ("monitor_formal", "Safety monitor + bounded formal", 3, 1, 1, 1, 0.75, 0, "governor + PWM proven for every state (19 of 21 mutants refuted); monitor; predictor not established"),
 ("lint_cdc", "Lint, synth, CDC scripts", 2, 1, 1, 1, 0.35, 0, "CDC now follows every boundary input (11 negative tests); structural only, generic Yosys"),
 ("ci", "CI workflow", 2, 1, .5, 0, 0, 0, "never run on GitHub (nothing pushed)"),
 ("hazard", "Hazard analysis + traceability checker", 3, 1, 1, 1, 0, 0, "no external review; several hazards open"),
 ("drv", "DRV8871 safe-state analysis", 2, 1, .5, 0, 0, 0, "datasheets unobtainable here; facts tagged by source quality"),
 ("calib", "Calibration tooling and guide", 3, 1, 1, 1, 0, 0, "tested on synthetic data; no real measurement"),
 ("paper", "Paper", 3, 1, 1, .5, 0, 0, "numbers checked against result files; references: full text unread"),
 ("deck", "Presentation deck", 2, 1, 1, .5, 0, 0, "audited and corrected; claim wording is the author's"),
 ("video", "Demo video", 2, 1, 1, .5, 0, 0, "claims check passes on a pinned snapshot; not re-rendered"),
 ("quartus", "Quartus build and timing closure", 4, .5, 0, 0, 0, 0, "project generator only; Quartus unavailable"),
 ("wokwi", "Wokwi run", 2, 1, 0, .5, 0, 0, "sketch prepared and consistency-checked; never run"),
 ("hw_estop", "Hardware e-stop cut / stuck-PWM protection", 4, 0, 0, 0, 0, 0, "recommended, not designed or built"),
 ("bringup", "Hardware bring-up and validation", 6, 0, 0, 0, 0, 0, "BLOCKED: no board, sensor, driver or motor"),
]
DIMS = ["written", "implemented", "tested", "verified", "hardware"]
def score():
    tw = sum(f[2] for f in F); out = {d: round(100 * sum(f[2] * f[3 + i] for f in F) / tw, 1) for i, d in enumerate(DIMS)}
    return tw, out
if __name__ == "__main__":
    tw, out = score()
    rows = [dict(id=f[0], name=f[1], weight=f[2], **{d: f[3 + i] for i, d in enumerate(DIMS)}, note=f[8]) for f in F]
    with open(os.path.join(ROOT, "results", "completion_score.json"), "w") as fh: json.dump(dict(percent=out, total_weight=tw, features=rows), fh, indent=1)
    print("dimension     percent"); [print(f"{d:12s}  {out[d]:5.1f}") for d in DIMS]
    if "--table" in sys.argv:
        print("\n| Feature | Weight | Written | Implemented | Tested | Verified | Hardware | Note |\n|---|---|---|---|---|---|---|---|")
        for f in F: print(f"| {f[1]} | {f[2]} | {f[3]:g} | {f[4]:g} | {f[5]:g} | {f[6]:g} | {f[7]:g} | {f[8]} |")
