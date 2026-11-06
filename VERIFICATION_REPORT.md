# Verification report

Scope: simulation, formal proofs of two RTL modules, and software tests of the RTL, the host program and the ML pipeline. **No hardware, Quartus, Wokwi or real-sensor evidence exists.**
The tables and counts below were read from the generated result files (`results/*.json`) by a script when this report was written; the explanatory text was written by hand. Strict "independently verified" credit is capped (see `PROJECT_COMPLETION_TRACKER.md`) because every technique was built inside this project and none has outside review.

## 1. Regression (19 testbenches, 4640 assertions, 0 failures)

`tools/run_regression.py` runs the manifest `sim/testbenches.txt`. A testbench passes only with exactly one summary line, no failed or vacuous assertion, no compiler warning, a clean exit and no output line starting with FAIL, MISMATCH, TIMEOUT or ERROR. The runner itself is tested with deliberately broken testbenches (`tests/test_regression_runner.py`).
**Composition of the total: 688 directed assertions + 3952 per-vector invariant evaluations in the two replay testbenches.** The total is not a coverage measure. `tb_pred_governor` compares 4,720 vectors but is **one aggregate assertion** (its summary says so).

| Testbench | Pass | Fail | Vectors | Note |
|---|---|---|---|---|
| `tb_adc_interface` | 17 | 0 | 0 | directed assertions only |
| `tb_input_conditioning` | 12 | 0 | 0 | directed assertions only |
| `tb_force_lut` | 12 | 0 | 0 | directed assertions only |
| `tb_safety_governor` | 28 | 0 | 0 | directed assertions only |
| `tb_pwm_generator` | 12 | 0 | 0 | directed assertions only |
| `tb_fault_handler` | 13 | 0 | 0 | directed assertions only |
| `tb_ai_control_interface` | 9 | 0 | 0 | directed assertions only |
| `tb_uart_link` | 15 | 0 | 0 | directed assertions only |
| `tb_uart_framing` | 45 | 0 | 49 |  |
| `tb_top` | 48 | 0 | 0 | directed system scenarios |
| `tb_de2_115_top` | 23 | 0 | 0 | directed board-wrapper scenarios; DEBOUNCE_CLKS=4 |
| `tb_pred_governor` | 1 | 0 | 4720 | RTL slope predictor vs Python reference; ONE aggregate assertion (zero mismatches over all vectors), not one per vector |
| `tb_pred_system` | 8 | 0 | 0 | directed ramps, predictor on vs off |
| `tb_replay` | 1976 | 0 | 1800 | SIMULATED ADC vectors; pass = invariant evaluations (cmd<=LUT per vector + safe-state and override-flag per over-limit v |
| `tb_replay_adversarial` | 1976 | 0 | 1800 | SIMULATED ADC vectors; pass = invariant evaluations (cmd<=LUT per vector + safe-state and override-flag per over-limit v |
| `tb_reset_recovery` | 50 | 0 | 14 | DEBOUNCE_CLKS=32 in simulation; 1000000 on the board |
| `tb_debounce` | 35 | 0 | 9 | button_debounce+reset_sync only; board uses N=1000000 |
| `tb_host_link` | 158 | 0 | 48 | host packet builder -> uart_tx -> ai_uart_bridge -> ai_control_interface; 36 accepted, 12 rejected |
| `tb_telemetry_tx` | 202 | 0 | 65 | telemetry_tx alone, decoded by an independent uart_rx; PERIOD=1000 |

## 2. Mutation testing (49 mutants)

`tools/mutation_test.py` applies one hand-written single edit to a temporary copy of the RTL and runs the whole regression: **49 of 49 detected, 0 survived, 0 invalid** (`results/mutation_report.json`).
`tools/mutation_audit.py` confirms for every mutant that the pattern occurs once in the intended file, the mutant compiles, it is detected by a **failed assertion** (not a warning or a bare timeout), and the real `rtl/`, `tb/` and manifest hashes are unchanged (`results/mutation_audit.json`: applied and compiled 49, killed by a failed assertion 49, real files unchanged: True).

| Area | Mutants | IDs |
|---|---|---|
| Safety governor, limits, AI caps | 17 | M01, M02, M03, M04, M05, M06, M07, M08, M09, M10, M11, M12, M43, M44, M45, M46, M47 |
| PWM kill, period boundary, compare | 4 | M13, M42, M48, M49 |
| Fault handling, ADC, conditioning, LUT | 7 | M14, M15, M16, M17, M18, M21, M22 |
| AI link and telemetry | 4 | M19, M20, M24, M25 |
| UART receiver/transmitter | 10 | M23, M27, M28, M29, M30, M31, M32, M33, M34, M35 |
| Keys, reset, synchronisers | 7 | M26, M36, M37, M38, M39, M40, M41 |

**Robustness of single-assertion kills.** The release audit found that six kills rested on one assertion. Independent assertions were added; the audit now enforces targets (distinct failing assertions / distinct testbenches):

| Mutant | Failing assertions | Testbenches | Required | Result |
|---|---|---|---|---|
| M06 | 2 | 1 | 2 / 1 | MET |
| M11 | 88 | 2 | 2 / 2 | MET |
| M17 | 3 | 2 | 2 / 2 | MET |
| M25 | 66 | 2 | 2 / 2 | MET |
| M40 | 7 | 2 | 2 / 2 | MET |
| M41 | 3 | 3 | 2 / 2 | MET |

M06 ("not armed" wait removed) cannot be seen at system level, because the latched e-stop holds the safe state after reset anyway (defence in depth), so its second observer is the formal property P11/P12, not a second testbench. After this phase, kills resting on exactly one testbench: M01, M06, M07, M12, M14, M23, M26, M27, M28, M34, M35, M38, M48; on exactly one assertion: none (boundary conditions such as an off-by-one threshold are visible only at the boundary value; where listed they are inherent, not an oversight).
Defects found by the campaign and fixed: an invalid mutant (M26), a kill by timeout (M39), a floating-reset "kill" (old M40), a survivor that exposed a missing wrapper-reset test (M40), and **M48 (PWM loads the duty every clock), which survived every simulation until an exact period-boundary assertion was added to `tb_pwm_generator`**. **Limits:** hand-written, single-edit, RTL-only mutants by the same author as the tests; a full score shows sensitivity to those faults, not completeness; equivalent mutants cannot be excluded.

## 3. Safety-invariant monitor (`tb/safety_monitor.v`)

Six invariants checked on every clock in `tb_top`, `tb_replay` (both modes), `tb_pred_system`, `tb_de2_115_top`, `tb_reset_recovery` and the co-simulation: S1 a safe state carries zero command; S2 PWM low one clock after safe state; S3 e-stop, sensor fault or invalid ADC force the safe state; S4 a force at or above the limit forces the safe state; S5 the command never exceeds the LUT command; S6 reset forces the safe state. No violation on the RTL; the safety-specific mutants M42 to M47 are each flagged by the monitor.

## 4. Formal verification (`formal/pwm_props.v`, `formal/gov_props.v`, `tools/formal_check.py`, `results/formal_report.json`)

**Why the earlier check was replaced (D-2).** The previous harness forced reset at step 1 and checked 14 clocks. The PWM loads a new duty only when its 12-bit counter wraps (every 4,096 clocks), so within 14 clocks of reset the active duty is 0 and the output is low whether or not the kill works: property P2 was vacuous, and mutants M13 and M42 (kill removed) were not refuted.
**What is checked now.** Each property is a one-step relation of the transition function. It is checked with Yosys `sat` **from a free initial state** (all registers arbitrary, inputs free every clock) on instrumented copies of `pwm_generator` and `safety_governor` that only add output ports (`dbg_cnt`, `dbg_da`, `dbg_armed`, `dbg_force_over`). No counterexample means the property holds in every state the module can reach, for all inputs: for the PWM that includes every counter value of the 4,096-clock period, so the update interval is covered by construction (W3 proves the counter advances by one per clock, W4 that the active duty changes only at the wrap).

| Class | Content |
|---|---|
| **PROVEN** (every state and input of `safety_governor` + `pwm_generator`) | W1 kill forces the output low next clock; W2 reset clears output/duty/counter; W3 counter +1 per clock (period 4,096); W4 duty loaded only at the period boundary; W5 output = compare(counter, active duty) unless killed; W6 zero duty never high. P1 safe state carries no command; P2 PWM low after safe state (through the real PWM stage); P3 e-stop/sensor fault/invalid ADC force the safe state; P4 valid force >= FORCE_MAX forces it; P5 command <= LUT command; P6 reset forces it; P7/P8 override and AI-used flags exact; P9/P10 AI class 2/3 caps; P11/P12 arming; P13 force latch with hysteresis; P14 latch forces the safe state; P15 (predictor off) safe state for exactly the documented causes |
| **BOUNDED** | none claimed |
| **NOT ESTABLISHED** | the slope predictor, the LUT, `fault_handler`, `button_debounce`, `reset_sync`, UART, `ai_control_interface` timeout/integrity, the host, multi-clock liveness, timing, analogue/physical behaviour |

Real RTL: P1-P14 (governor + PWM, PRED_EN=1): holds, P1-P15 (governor + PWM, PRED_EN=0): holds, W1-W6 (PWM): holds. **Negative controls:** every governor/PWM mutant through the same check: **19 of 21 refuted**; not refuted: M07, M12 (the slope-predictor mutants, not asserted formally).

| Mutant | Description | Formal check |
|---|---|---|
| M01 | force limit uses > instead of >= | refuted |
| M02 | hysteresis removed (release at FORCE_MAX) | refuted |
| M03 | e-stop not a trip cause | refuted |
| M04 | sensor fault not a trip cause | refuted |
| M05 | invalid ADC not a trip cause | refuted |
| M06 | 'not armed' wait removed | refuted |
| M07 | predictive trip ignored | **not refuted** |
| M08 | AI class-2 cap removed | refuted |
| M09 | AI class-3 uses wrong cap | refuted |
| M10 | command not zeroed on trip | refuted |
| M11 | override flag ignores class 3 | refuted |
| M12 | predictor look-ahead K ignored | **not refuted** |
| M13 | PWM kill removed | refuted |
| M42 | PWM ignores the kill input | refuted |
| M43 | governor does not zero the command on trip | refuted |
| M44 | invalid ADC no longer trips the governor | refuted |
| M45 | AI class 2 can RAISE the command to HOLD_CAP | refuted |
| M46 | force limit comparison disabled | refuted |
| M47 | governor reset leaves safe_state low | refuted |
| M48 | PWM loads the duty every clock (not only at the period bound | refuted |
| M49 | PWM compare uses <= (a zero duty still gives a pulse) | refuted |

These are proofs about two modules as written. They do not show that the properties are the right requirements, and say nothing about the other modules, timing or hardware. Yosys `sat` is a bounded-model-checking engine; the "all states" claim rests on each property being a one-step relation, which holds by construction of the harness (delayed copies `p_*` are skipped for the first two steps).

## 5. Structure, lint and synthesis

* `tools/cdc_check.py` follows **every input bit of `de2_115_top` and `tactile_reflex_top`** (29 bits) through the module hierarchy and requires each use to be a recognised synchroniser (two-flop shift capture, two-stage chain, async-assert/sync-release reset chain, a connection to a child port that is itself one, or a clock); anything else is a violation, so a newly added unsynchronised input cannot pass silently (the previous checker used a fixed list of five inputs). Result: 26 bits synchronised, 2 clock, 1 unused (`KEY[2]`). `tests/test_cdc_check.py` has 11 negative tests (new raw flop, new input used combinationally, synchroniser bypassed, removed, broken e-stop chain, raw wrapper reset, stray async-reset flop, second clock) plus acceptance of a correct new synchroniser. Vector ports are analysed as a whole. Textual, not a commercial CDC analysis; no MTBF.
* `tools/lint_synth.sh`: Icarus `-Wall` clean, Yosys elaboration and `check -assert` clean (no latches, no combinational loops; both verified to fire on broken copies), generic LUT4 mapping about 625 LUT4 and 466 flip-flops (`results/synth_report.json`). **Not a Quartus fit, no timing.**

## 6. Host, ML, pins, calibration, Quartus generator (Python tests)

| Area | Evidence |
|---|---|
| Host program | 25 mock-serial tests (packet format, exhaustive telemetry round-trip, parser split-point/garbage/dropped-byte/lookalike tests, stale detection, reconnect budget, clean shutdown); breaking the parser, the retry reset or the AI write is caught |
| JSON model | schema and cycle validation; 0 prediction differences vs scikit-learn on 240,000 simulated samples (`tests/test_host.py`, which needs the legacy pickle left on disk); the release audit additionally checked 3,600 threshold-boundary and 50,000 random vectors against a fresh retrain with a scratch script that is not in the repository; a test forbids pickle in runtime code |
| ML validation (simulated) | grouped 5-fold accuracy 0.926 +/- 0.008 vs force-only 0.862; label-shuffle control 0.529 (majority 0.530); excessive-force recall 0.72 (`results/ml_validation.json`) |
| Real-data pipeline | runs on a labelled **simulated fixture**; rejects 11 kinds of malformed input; never overwrites the project model |
| Calibration | arithmetic checked on an exact curve; refuses too few loads/readings, non-monotonic data, a limit beyond the data |
| Pin checker, Quartus generator | tested on synthetic reference files; a refused generator run now leaves no directory behind; real pins unverified |
| ADC timing | `tests/test_adc_timing.py` pins the simulated delay tolerances quoted in section 8 |

## 7. Integration: host-in-the-loop co-simulation (`tools/cosim_host_rtl.py`, `tb/cosim_harness.v`, `results/cosim_report.json`)

The real host code (parser, feature stream, JSON model, packet builder) against the real board RTL (`de2_115_top`, real UART), over a 52-step trace with 145 telemetry frames per pass: no contact, light contact, ramp, hold just below the limit, trip at 2560, hysteresis band (2559, 2400 and 2304 stay safe; 2303 releases), a fast jump over the limit, an e-stop at mid force (release, stay latched, clear, resume), an e-stop at over-limit force (stop released while still over the limit; clear ignored while the cause persists), ADC frame errors (sensor fault latches, stays after recovery, clear resumes), operator clear presses.
**Six passes:** A no AI; B the real model (all four classes occur); C hostile always-class-2; D hostile always-class-3; E host dies after a third of the run (heartbeat timeout must drop the AI); F corrupted link (bad checksum carrying a *different* class, wrong header, garbage, and packets whose class/inverse bits disagree despite a valid checksum, mixed with good ones: {'badchk': 18, 'badhdr': 18, 'garbage': 18, 'good': 72, 'incons': 18}). An **independent reference model** (written separately from the RTL: hysteresis latch, e-stop latch, sensor-fault latch, clears only when the cause is gone) predicts, per settled frame, the safe state, sensor fault, e-stop latch, command (`min(LUT, cap[class])`), AI validity and AI class; the RTL's values and the telemetry flags decoded by the host parser must equal them, and a safe state must always carry command 0 and PWM low.

| Pass | Settled frames checked | Over-limit | Hysteresis band | E-stop pressed | E-stop latched after release | Sensor fault active | Sensor fault latched after | AI-valid frames | Frames where the AI cap lowered the command |
|---|---|---|---|---|---|---|---|---|---|
| A | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 0 | 0 |
| B | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 120 | 35 |
| C | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 120 | 45 |
| D | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 120 | 51 |
| E | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 43 | 13 |
| F | 120 | 20 | 6 | 12 | 10 | 8 | 7 | 90 | 27 |

Result: PASS; the host parser decoded 144 of 145 frames with 0 dropped bytes (the last frame needs the next header to be confirmed). Minimum coverage counts are asserted in the tool and again in `tests/test_cosim.py`.
**Negative controls** (`tools/cosim_negative_controls.py`, `results/cosim_negative_controls.json`): single-edit faults injected into a copy of the RTL; the co-simulation must fail on each. **11 of 11 detected.**

| Mutant | Description | Co-simulation |
|---|---|---|
| M02 | hysteresis removed (release at FORCE_MAX) | detected |
| M03 | e-stop not a trip cause | detected |
| M04 | sensor fault not a trip cause | detected |
| M08 | AI class-2 cap removed | detected |
| M09 | AI class-3 uses wrong cap | detected |
| M10 | command not zeroed on trip | detected |
| M19 | AI integrity check disabled | detected |
| M20 | AI heartbeat timeout disabled | detected |
| M24 | AI packet checksum ignored | detected |
| M25 | telemetry header byte changed | detected |
| M46 | force limit comparison disabled | detected |

**Limits:** open loop (the host answers from telemetry but its answers do not feed back into the ADC trace); ideal UART; behavioural ADC with zero output delay; the model's classes come from features computed at an 80 us cadence although it was trained at 500 us, so they are not meaningful grasp classes (the link and the limit behaviour are what is tested, not AI quality).
The board-level signal chain (ADC, conditioning, LUT, predictor, governor, PWM, faults, UART/AI, watchdog, e-stop, reset) is exercised end to end by `tb_top`, `tb_de2_115_top`, `tb_pred_system`, `tb_replay*` and `tb_reset_recovery`.

## 8. ADC output-delay tolerance of the RTL (H-16, `tools/adc_timing_sweep.py`, `results/adc_timing_sweep.json`)

The behavioural ADC model has zero output delay. The sweep builds a temporary copy of it that delays every MISO update by a programmable time after the SCLK falling edge (and the first bit after chip-select falls), and runs `tb_top`, with the RTL as it is and with the MISO synchroniser removed:

| Variant | Largest passing delay | Smallest failing delay | Delays tried (P/F/T) |
|---|---|---|---|
| with_synchroniser | 20 ns | 22 ns | 0:P 10:P 20:P 22:F 30:F 40:F 50:F 60:F 62:F 70:F 80:F 100:T |
| without_synchroniser | 60 ns | 62 ns | 0:P 10:P 20:P 22:P 30:P 40:P 50:P 60:P 62:F 70:F 80:F 100:F |

Why: with the synchroniser each bit is sampled 4 clocks (80 ns) after the ADC launches it, and the first bit (the frame-error indication) only 1 clock (20 ns) after chip-select falls; without it 6 clocks (120 ns) and 3 clocks (60 ns). The failing checks at larger delays are the three invalid-frame checks of `tb_top`.
**This is the RTL's own sampling window against an idealised delay. It is not a hardware margin.** The real AD7476A output delay and the board/pin delays are unverified (datasheet unobtainable, no scope measurement); the 60 ns figure for the original wiring is not evidence that it is safe, and no timing guarantee is claimed in either direction. H-16 remains an unresolved hardware blocker; the decision on the MISO structure has not been made.

## 9. Model versus RTL experiments

159 scripted checks: model 159/159, RTL 157/159 (the two misses are a stimulus-granularity artefact: scenario S06a became about 240 invalid frames in the RTL), baseline 93/159 by design; 13 of 839 step comparisons differ, all in S06a/b/d, explained and confirmed by the frame-level (577 frames, 0 differences) and step-expansion (839 steps, 0 differences) checks. `tools/check_experiments.sh` and `tools/check_validation.sh` reproduce all of these byte-identically on the current RTL. The time-based watchdog model was adopted with the author's approval; it follows the RTL's 2000-clock rule, so the model is not an independent oracle.

## 10. What this verification does not show

Behaviour of real components (ADC output delay, driver, sensor), timing closure, metastability probability, power-up pin states, mechanical effects, long-term drift, a hung or clock-less FPGA, the slope predictor formally, or anything about real force data. See `HAZARD_ANALYSIS.md` for the hazards that remain open, in particular H-16.
