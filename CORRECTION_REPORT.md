# Correction report

Phase: 2026-11-06, approved by Sanjiv after `FINAL_RELEASE_READINESS_AUDIT.md`. Nothing was committed, pushed, reset, cleaned or deleted; the branch is unchanged (`claude/keen-hypatia-wvyqpy`, HEAD `96b5025`).
**Outside this authorisation and therefore NOT done: any change to the MISO RTL logic, and all physical hardware work.** The only RTL edit is a comment.

## 1. What was found while correcting

* **D-2 cause confirmed.** The PWM loads a new duty only when its 12-bit counter wraps (every 4,096 clocks). The old harness forced reset at step 1 and checked 14 clocks, so the active duty was always 0 and the output low whether or not the kill worked: property P2 was vacuous and mutants M13/M42 were not refuted.
* **New simulation gap.** While building the formal check, a new PWM mutant (**M48: duty loaded every clock instead of at the boundary**) was *refuted by the formal check but survived every testbench*. The "duty change is applied only at the period boundary" assertion was vacuous (it accepted 1024 to 4080). An exact period-boundary assertion was added; M48 is now killed.
* **Co-simulation now agrees with an independent reference model** on every settled frame in six passes: no discrepancy between the RTL and the reference (the coverage minima, not the behaviour, needed work).
* **The ADC timing numbers are reproducible.** They had been measured ad hoc; they are now a tool plus a pinned test.

## 2. Changed files and reasons

New (10): `formal/pwm_props.v` (W1-W6, PWM properties); `tools/formal_check.py` (instrumented copies, proofs, formal-vs-mutants matrix); `tools/adc_timing_sweep.py` and `tests/test_adc_timing.py` (D-1 characterisation, pinned); `tools/cosim_negative_controls.py` (11 injected faults); `tests/test_cdc_check.py` (11 negative tests); `tb/tb_telemetry_tx.v` (independent observer for the telemetry header, M25); `results/formal_report.json`, `results/cosim_negative_controls.json`, `results/adc_timing_sweep.json` (generated).

Modified (42):

| File(s) | Reason |
|---|---|
| `rtl/tactile_reflex_top.v` | **comment only**: states the 20 ns first-bit window, the 80 ns data-bit sampling point, that the real ADC timing is unverified and the decision pending (D-1). No logic changed |
| `HAZARD_ANALYSIS.md` | H-16 rewritten; requirement rows re-tagged (PROVEN / SIM); new section on formal classes (PROVEN, BOUNDED none, NOT ESTABLISHED) (D-1, D-2) |
| `VERIFICATION_REPORT.md` | regenerated from the result files: counts decomposed, mutation robustness, formal rewrite, CDC rewrite, co-simulation rewrite, new ADC-timing section |
| `paper/paper.md` | abstract, 5.4 verification bullets, 6.4 limits (MISO hazard), conclusion, reproducibility commands |
| `README.md`, `FINAL_PROJECT_AUDIT.md`, `HARDWARE_VALIDATION_GUIDE.md`, `REPRODUCIBILITY_GUIDE.md` | corrected H-16 wording, new counts and commands, stage-2 scope-measurement gate |
| `PROJECT_COMPLETION_TRACKER.md`, `tools/completion_score.py`, `results/completion_score.json` | recalculated percentages and inventory |
| `CHANGELOG_IMPLEMENTATION.md` | correction-phase section; D-9 omissions now stated |
| `FINAL_RELEASE_READINESS_AUDIT.md` | status-after-correction section; original text kept and marked superseded where it differs |
| `formal/gov_props.v`, `tools/formal_check.sh` | rewritten as free-state one-step proofs P1-P15; shell wrapper now calls `tools/formal_check.py` (D-2) |
| `tools/mutation_test.py` | PWM mutants M48, M49 added (49 total) |
| `tools/mutation_audit.py` | counts distinct failing assertions and testbenches (the old count double-counted), enforces robustness targets for M06, M11, M17, M25, M40, M41 |
| `tools/cdc_check.py` | rewritten: follows every boundary input bit through the hierarchy (D-6) |
| `tools/cosim_host_rtl.py`, `tb/cosim_harness.v`, `tests/test_cosim.py` | rewritten/extended: fault conditions, six host behaviours, independent reference model, coverage minima, negative controls (D-5) |
| `tools/make_quartus_project.py`, `tests/test_quartus_project.py` | validate before creating the output directory (D-7); test added |
| `tools/check_traceability.py` | reads the new formal property IDs |
| `tb/tb_pwm_generator.v` | exact period-boundary assertions (kills M48) |
| `tb/tb_safety_governor.v`, `tb/tb_input_conditioning.v`, `tb/tb_top.v`, `tb/tb_replay.v`, `tb/tb_de2_115_top.v`, `tb/tb_reset_recovery.v` | extra independent assertions for the six formerly single-assertion kills (override flag per class, arming after a second reset, rail threshold at unit and system level, wrapper reset on a half-received AI packet and on the two-clock release); nothing was removed or loosened |
| `tb/tb_pred_governor.v` | summary now `VECTORS 4720` and states it is one aggregate assertion (D-4) |
| `sim/testbenches.txt`, `sim/run_all.sh`, `.github/workflows/ci.yml` | register `tb_telemetry_tx`; call the timing sweep; CI runs the co-simulation negative controls in the optional job |
| `results/mutation_report.json`, `mutation_audit.json`, `regression_summary.json`, `cosim_report.json`, `sim_log.txt`, `sim_console.png`, `trace_estop.csv` | regenerated outputs. `trace_estop.csv` (tracked) changed by an absolute cycle offset only (the extra `tb_top` assertions shift the timeline; relative timing is identical, verified; the demo-video claims check still passes) |

## 3. Verification commands and results (run on the final tree)

| Command | Result |
|---|---|
| `sh sim/run_all.sh` | exit 0, `ALL TESTBENCHES PASSED` (includes the CDC, pin, Wokwi, lint/synth, formal, 74 unit tests, timing sweep, regression) |
| `python3 tools/run_regression.py` | `19 testbenches, 19 passed, 0 failed; assertions passed=4640 failed=0` (688 directed + 3,952 replay evaluations) |
| `python3 tools/mutation_test.py --jobs 6` | `mutants 49: killed 49, survived 0, invalid 0` |
| `python3 tools/mutation_audit.py` | `applied+compiled=49 killed-by-failed-assertion=49 real_rtl_tb_unchanged=True`; kills resting on one assertion: none; targets M06, M11, M17, M25, M40, M41: MET |
| `sh tools/formal_check.sh` | `PROVEN` for W1-W6, P1-P15 (predictor off), P1-P14 (predictor on); `19 of 21 governor/PWM mutants refuted; not refuted: ['M07', 'M12']` |
| `python3 tools/cosim_host_rtl.py` | `PASS`, 145 telemetry frames, 144 decoded, 0 dropped; 120 settled frames checked in each of six passes |
| `python3 tools/cosim_negative_controls.py` | `co-simulation detects 11 of 11 injected faults` |
| `python3 tools/cdc_check.py -v` | 29 boundary input bits: 26 synchronised, 2 clock, 1 unused (`KEY[2]`) -> OK |
| `python3 tools/adc_timing_sweep.py` | with synchroniser: passes to 20 ns, fails from 22 ns; without: passes to 60 ns, fails from 62 ns (simulation only) |
| `python3 tools/check_artifacts.py`; `sh tools/check_experiments.sh`; `sh tools/check_validation.sh` | all byte-identical on the current RTL |
| `python3 tools/check_traceability.py` | `16 hazards, 17 requirements ... -> OK` |
| tree integrity | RTL, testbench, manifest, formal, tool and test hashes identical before and after the sequences; `FINAL_RELEASE...`/`CORRECTION_REPORT.md` and the verification backup, see section 5 |

## 4. Percentages (recalculated, `python3 tools/completion_score.py --table`)

| Dimension | Before this phase (tracker / audit estimate) | Now |
|---|---|---|
| Implementation | 77.6 % / about 76 % | **76.5 %** |
| Simulation testing | 76.8 % / about 77 % | **76.8 %** |
| Independent verification (strict, capped, all evidence internal) | 28.5 % / about 26 % | **31.4 %** |
| Hardware validation | 0 % | **0 %** |

## 5. Backup

The earlier backups (`baseline_20261106T0838Z`, `final_20261106T1036Z`) are untouched. A new set `corrected_phase2_20261106` (tar.gz, SHA-256, manifest, git bundle, tracked diff) is in `backups_exec/`; its checksum was verified, it was extracted into an empty directory and compared with the live tree, and the extracted copy ran the regression. The tarball contains this report; its SHA-256 is delivered next to it rather than written inside it.

## 6. Still open (not changed, by instruction or by necessity)

H-16 (MISO structure decision and real ADC timing), the FPGA-only e-stop, configuration-time pin state, stuck PWM, unverified pins, uncalibrated thresholds, slope predictor not formally established, stale demo video, deck title and slide 9 ratings, paper references unread, CI never run, everything hardware.
