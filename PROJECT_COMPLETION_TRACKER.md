# Project completion tracker

Last updated 2026-11-06 after the execution pass and the correction phase (audit baseline: commit `96b5025`, previously about 78 % implemented, 70.5 % tested, 21.4 % independently verified).
**Nothing is committed or pushed. Hardware validation is 0 %: no board, sensor, driver, motor, Quartus or Wokwi run exists.** Percentages are computed, not guessed, and are conservative; items that need hardware or an unobtainable document are marked **BLOCKED** and score 0 for what they would need.

## What percentage is complete?

Weighted by feature importance (`tools/completion_score.py`, 32 features, inventory below; scores are listed so they can be challenged). Recalculated after the correction phase:

| Dimension | Percent | Meaning |
|---|---|---|
| Code / documents written | **86.8 %** | the artefact exists |
| Implemented | **76.5 %** | does what it is meant to, in simulation or on the host; 0 for anything that cannot run here; the unresolved ADC-line structure (H-16) is only partly credited |
| Tested | **76.8 %** | automated tests exist and pass |
| Independently verified (strict) | **31.4 %** | evidence beyond the author's own tests (audited mutation, monitor, formal proofs, byte-exact reproduction, co-simulation); capped at 0.75 per feature because all of it was produced inside this project with no outside review |
| Hardware validated | **0.0 %** | nothing was run on hardware |

History: the first pass reported 77.6 / 76.8 / 28.5 / 0; the release audit's own estimate was about 76 / 77 / 26 / 0 after finding the PWM formal property vacuous and the MISO hazard understated; after the correction phase the figures are 76.5 / 76.8 / 31.4 / 0. The verified figure rises because the formal check is now a real proof for the governor and PWM (19 of 21 mutants refuted), the co-simulation is checked against an independent reference model with fault conditions and six host behaviours (11 of 11 injected faults detected), the CDC check covers every boundary input, and six single-assertion kills were strengthened; it is **still capped** and nothing in it has outside review. The "tested" figure does not move because every feature already counted as tested; the new tests raise confidence, not the weighted count.

Task view (21 original tasks plus the correction phase): all achievable work is executed; the gap is BLOCKED work and decisions. Mean original-task completion is unchanged at **85 %** except T7 (see below).

## Phase and task status

| Phase | Task | Status | % | Blocked / remaining |
|---|---|---|---|---|
| 1 | T1 repository hygiene | done | 100 | pickle kept on disk (untracked), by design |
| 1 | T2 dependencies | done | 100 | verified in a fresh virtual environment |
| 1 | T3 regression and CI | regression done; CI written, never run | 85 | **BLOCKED**: CI cannot run without pushing |
| 2 | T4 UART framing tests, mutation re-run | done (RTL repair found and made) | 100 | |
| 2 | T5 reset sync, debounce, testbenches | done | 100 | board debounce (20 ms) simulated only at 32 clocks |
| 2 | T6 testbench reporting | done | 100 | |
| 2 | T7 safety assertions, formal | **done: governor and PWM proven for every state; predictor not established** (the first-pass 14-clock check was vacuous for the PWM and was replaced) | 100 | `sby` unavailable (the engine is Yosys `sat`) |
| 2 | T8 lint, synth, CDC automation | done; CDC checker now follows every boundary input | 100 | Quartus numbers **BLOCKED** |
| 3 | T9 host hardening, mock serial | done | 100 | real serial port not available |
| 3 | T10 pickle -> JSON model | done | 100 | |
| 3 | T11 ML validation, real-data pipeline | done on simulated data; pipeline tested on a fixture | 80 | **BLOCKED**: no real recordings |
| 4 | T12 pin verification | checker, emitter, tests done; pins still unverified (24/41 bits unassigned) | 40 | **BLOCKED**: Terasic file not obtainable (host not allowed) |
| 4 | T13 Quartus project | generator done (validates before creating anything); never built | 50 | **BLOCKED**: Quartus not installed |
| 4 | T14 calibration | tool, template, guide done | 70 | **BLOCKED**: no real measurements |
| 4 | T15 DRV8871 analysis | analysis done with sources tagged | 60 | **BLOCKED**: TI datasheet not obtainable |
| 4 | T16 hazard analysis, traceability | done (16 hazards, 17 requirements, checker); H-16 corrected | 100 | several hazards remain OPEN by nature, H-16 is an unresolved hardware blocker |
| 5 | T17 Wokwi | prepared and consistency-checked; never run | 50 | **BLOCKED**: login and host |
| 5 | T18 experiments, 13 mismatches | done: reproduces on the hardened RTL; mismatches classified and confirmed | 100 | |
| 6 | T19 paper | complete draft, corrected | 90 | references: metadata verified earlier, not re-verifiable now, **no full text read** |
| 7 | T20 deck | audited and corrected | 90 | title "Latency-Optimal" and DRV8871 ratings flagged for the author |
| 7 | T21 video | audited; claims pinned to a snapshot; not re-rendered | 70 | decision needed |
| C | Correction phase (approved 2026-11-06): D-1 documentation, D-2 PWM formal, CDC checker, co-simulation, single-assertion kills | done | 100 | the MISO RTL decision and all hardware work remain outside the authorisation |

## Evidence summary (all regenerate with `REPRODUCIBILITY_GUIDE.md`)

| Item | Result |
|---|---|
| RTL regression | 19 testbenches, 4,640 assertions (688 directed + 3,952 per-vector replay evaluations), 0 failures (`results/regression_summary.json`) |
| Mutation campaign | 49 mutants, 49 detected, 0 survived, 0 invalid; audited with robustness targets (`results/mutation_report.json`, `results/mutation_audit.json`) |
| Formal | governor and PWM proven for every state (W1-W6, P1-P15); 19 of 21 governor/PWM mutants refuted; predictor not established (`results/formal_report.json`) |
| Python tests | 74 tests pass (runner, host, model, real-data pipeline, calibration, pins, Quartus generator, CDC checker, ADC timing, co-simulation) |
| Co-simulation host <-> RTL | PASS: six passes, 120 settled frames each against an independent reference model; 11 of 11 injected faults detected (`results/cosim_report.json`, `results/cosim_negative_controls.json`) |
| ADC output-delay tolerance (simulation only) | 20 ns with the MISO synchroniser, 60 ns without; **not** a hardware margin (`results/adc_timing_sweep.json`) |
| Reproducibility checks | artifacts, experiments (159 checks, 13/839), frame (577) and step-expansion (839) validations: byte-identical on the current RTL |
| Generic synthesis | about 625 LUT4, 466 flip-flops (Yosys, not Quartus; no timing) |

## Open items that block a higher percentage

1. Pin verification and Quartus build/timing (needs Terasic's file and Quartus).
2. All hardware validation and calibration (needs the hardware and a person present).
3. Hardware safety design decisions: independent e-stop cut of the motor supply, configuration-time pin state, stuck-PWM protection, and **the MISO structure (H-16: first data bit sampled 20 ns after chip-select; real ADC timing unverified)**.
4. Real sensor data for the ML path.
5. Reference full-text review and the Wokwi run.
6. Running CI (requires pushing, which was not authorised).

## Feature inventory behind the percentages

| Feature | Weight | Written | Implemented | Tested | Verified | Hardware | Note |
|---|---|---|---|---|---|---|---|
| ADC SPI interface | 5 | 1 | 1 | 1 | 0.25 | 0 | M18, frame-level validation |
| Input conditioning / rail detection | 3 | 1 | 1 | 1 | 0.4 | 0 | M17 now seen by two testbenches |
| Force LUT | 3 | 1 | 1 | 1 | 0.25 | 0 | M21, artifact reproduction |
| Hard force limit + hysteresis + AI cap | 8 | 1 | 1 | 1 | 0.75 | 0 | mutants, monitor S1-S5, formal P1-P5,P7-P8 |
| Slope predictor | 4 | 1 | 1 | 1 | 0.25 | 0 | M07, M12; formal only with a 3-clock window |
| PWM generator + kill | 4 | 1 | 1 | 1 | 0.75 | 0 | M13, M42, M48, M49; monitor S2; formal W1-W6 proven for every counter value |
| Fault handler (e-stop, sensor, watchdog) | 7 | 1 | 1 | 1 | 0.5 | 0 | mutants, S3; formal treats its outputs as inputs |
| AI control interface | 4 | 1 | 1 | 1 | 0.75 | 0 | adversarial replay, M19, M20, M45, P5 |
| UART rx/tx/bridge | 5 | 1 | 1 | 1 | 0.5 | 0 | 49-vector framing test, 8 UART mutants, host_link; no real line |
| Telemetry transmitter | 2 | 1 | 1 | 1 | 0.5 | 0 | M25 killed by a unit testbench, the board testbench and the co-simulation |
| Reset sync, debounce, input synchronisers | 5 | 1 | 0.75 | 1 | 0.4 | 0 | M36-M41; CDC check over every boundary input; MISO structure unresolved (H-16): implemented only partly credited |
| Board wrapper (de2_115_top) | 4 | 1 | 1 | 1 | 0.35 | 0 | M26, M38-M40 (M40 now two testbenches); debounce simulated at 32 clocks only |
| DE2-115 pin assignments | 4 | 0.5 | 0 | 0.5 | 0 | 0 | 24 of 41 bits unassigned, none verified (checker + tests exist) |
| Timing constraints | 2 | 0.5 | 0 | 0 | 0 | 0 | minimal SDC, no timing report |
| Host software (parser, session, reconnect) | 4 | 1 | 1 | 1 | 0.5 | 0 | mock-serial tests; co-simulation with a reference model, six host behaviours and negative controls |
| ML model, JSON format, validation (simulated data) | 3 | 1 | 1 | 1 | 0.5 | 0 | grouped CV, shuffle control, byte-exact reproduction |
| Real-data ML pipeline | 3 | 1 | 0.5 | 1 | 0 | 0 | runs only on a simulated fixture; no real recordings |
| Regression runner and manifest | 3 | 1 | 1 | 1 | 0.5 | 0 | negative tests of the runner itself |
| Mutation framework + audit | 3 | 1 | 1 | 1 | 0.4 | 0 | 49 mutants; kills with one assertion addressed and audited; hand-written mutants only |
| Safety monitor + bounded formal | 3 | 1 | 1 | 1 | 0.75 | 0 | governor + PWM proven for every state (19 of 21 mutants refuted); monitor; predictor not established |
| Lint, synth, CDC scripts | 2 | 1 | 1 | 1 | 0.35 | 0 | CDC now follows every boundary input (11 negative tests); structural only, generic Yosys |
| CI workflow | 2 | 1 | 0.5 | 0 | 0 | 0 | never run on GitHub (nothing pushed) |
| Hazard analysis + traceability checker | 3 | 1 | 1 | 1 | 0 | 0 | no external review; several hazards open |
| DRV8871 safe-state analysis | 2 | 1 | 0.5 | 0 | 0 | 0 | datasheets unobtainable here; facts tagged by source quality |
| Calibration tooling and guide | 3 | 1 | 1 | 1 | 0 | 0 | tested on synthetic data; no real measurement |
| Paper | 3 | 1 | 1 | 0.5 | 0 | 0 | numbers checked against result files; references: full text unread |
| Presentation deck | 2 | 1 | 1 | 0.5 | 0 | 0 | audited and corrected; claim wording is the author's |
| Demo video | 2 | 1 | 1 | 0.5 | 0 | 0 | claims check passes on a pinned snapshot; not re-rendered |
| Quartus build and timing closure | 4 | 0.5 | 0 | 0 | 0 | 0 | project generator only; Quartus unavailable |
| Wokwi run | 2 | 1 | 0 | 0.5 | 0 | 0 | sketch prepared and consistency-checked; never run |
| Hardware e-stop cut / stuck-PWM protection | 4 | 0 | 0 | 0 | 0 | 0 | recommended, not designed or built |
| Hardware bring-up and validation | 6 | 0 | 0 | 0 | 0 | 0 | BLOCKED: no board, sensor, driver or motor |
