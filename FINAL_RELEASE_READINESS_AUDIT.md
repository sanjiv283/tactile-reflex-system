# Final release-readiness audit

Date: 2026-11-06. Branch `claude/keen-hypatia-wvyqpy`, HEAD `96b5025` (unchanged: no commit, push, merge, reset, clean, stash or branch change).
Scope: the working tree exactly as it stood after the implementation pass, checked against the final backup `final_20261106T1036Z`.
**Simulation readiness and physical-hardware readiness are different things. No physical validation evidence exists, so the project is not hardware-ready and is not called so anywhere below.**

## Status after the correction phase (2026-11-06, approved by Sanjiv)

This section **supersedes** the verdict table, the defect list and the final recommendation of the original audit below wherever they differ. The original audit text is kept unchanged below for the record. Details: `CORRECTION_REPORT.md`. The MISO RTL decision and all hardware work were **outside** the approved scope and have not been touched.

### Defects: before and after

| ID | Original finding | Status now | Evidence |
|---|---|---|---|
| D-1 | MISO margin understated everywhere | **Documentation corrected; hazard still OPEN.** The 20 ns tolerance with the synchroniser is reported accurately; the 60 ns result without it is stated not to be proof of safety; the real AD7476A timing is stated as unverified; H-16 is an unresolved hardware blocker; no RTL logic changed (comment only) | `rtl/tactile_reflex_top.v` comment, `HAZARD_ANALYSIS.md` H-16, `VERIFICATION_REPORT.md` section 8, `paper/paper.md` 6.4, README, `FINAL_PROJECT_AUDIT.md`, `HARDWARE_VALIDATION_GUIDE.md`; `python3 tools/adc_timing_sweep.py` (with: passes to 20 ns, fails from 22 ns; without: passes to 60 ns, fails from 62 ns); `tests/test_adc_timing.py` pins the numbers |
| D-2 | PWM kill formal property vacuous at depth 14 | **Fixed.** Cause confirmed (the PWM loads a duty only at the 4,096-clock counter wrap; the old harness forced reset and checked 14 clocks). New one-step transition properties W1-W6 and P1-P15 are checked from a free initial state on instrumented copies, so every counter value is covered. **19 of 21** governor/PWM mutants are refuted, including the deliberately broken PWM kill (M13, M42), duty-every-clock (M48) and compare (M49); the two not refuted are the slope-predictor mutants (M07, M12), documented as not established. Classes PROVEN / BOUNDED (none) / NOT ESTABLISHED are stated in the hazard analysis, verification report and paper | `python3 tools/formal_check.py`, `results/formal_report.json`, `formal/pwm_props.v`, `formal/gov_props.v` |
| D-3 | "4,236 assertions" conflates directed and replay | **Fixed** in README, paper, tracker, verification report: 4,640 = 688 directed + 3,952 per-vector replay evaluations | `results/regression_summary.json` |
| D-4 | `tb_pred_governor` said `VECTORS 0` | **Fixed**: `VECTORS 4720`, and it says it is one aggregate assertion | `tb/tb_pred_governor.v` |
| D-5 | co-simulation asserted too little | **Strengthened**: exact cap for every class, 52-step trace with e-stop at mid and over-limit force, ADC frame errors with latching and clear, hysteresis band, six host behaviours (real model, hostile class 2 and 3, host dies, corrupted link with four corruption types), an independent reference model, 120 settled frames per pass, asserted coverage minima, 11 of 11 injected faults detected. Remaining limits stated: open loop, ideal UART, behavioural ADC | `python3 tools/cosim_host_rtl.py`, `python3 tools/cosim_negative_controls.py` |
| D-6 | CDC checker missed a new unsynchronised input | **Fixed**: follows every boundary input bit (29) through the hierarchy; 11 negative tests including the new-raw-input case | `python3 tools/cdc_check.py -v`, `tests/test_cdc_check.py` |
| D-7 | Quartus generator left an empty directory | **Fixed** (validates first), test added | `tests/test_quartus_project.py` |
| D-8 | 6 kills rested on one assertion; M48 found | **Fixed**: independent assertions added; audit now counts distinct assertions and testbenches and enforces targets for M06, M11, M17, M25, M40, M41 (all MET). **No kill rests on exactly one assertion.** Kills resting on exactly one testbench (each with at least two assertions): M01, M06, M07, M12, M14, M23, M26, M27, M28, M34, M35, M38, M48. M06 is invisible at system level (the e-stop latch masks it), so its second observer is the formal property P11/P12. The campaign also found that **M48 survived every simulation**; an exact period-boundary assertion now kills it | `python3 tools/mutation_audit.py` |
| D-9 | changelog omissions | **Fixed** | `CHANGELOG_IMPLEMENTATION.md` |
| D-10 | audit touched two trace CSVs (content identical) | unchanged; disclosed | section 0 |
| D-11 | video stale, deck title, slide 9 | **OPEN** (author decisions) | `demo_video/README.md` |
| D-12 | work uncommitted; one backup | **OPEN until you approve a commit**; a new verified backup was taken after the correction phase | section below |

### Re-verified after the changes (commands run on the final tree)

| Area | Result | Evidence and exact command |
|---|---|---|
| Regression | **PASS**: 19 testbenches, 4,640 assertions (688 directed + 3,952 replay evaluations), 0 failures | `python3 tools/run_regression.py` |
| Mutation campaign | **PASS**: 49 of 49 detected, 0 survived, 0 invalid | `python3 tools/mutation_test.py --jobs 6` -> `results/mutation_report.json` |
| Mutation audit | **PASS**: 49 applied and compiled, 49 killed by a failed assertion, real RTL/testbench hashes unchanged, all six robustness targets MET | `python3 tools/mutation_audit.py` -> `results/mutation_audit.json` |
| Safety monitor | **PASS**: no violation; flags M42-M47 | inside the regression and the audit |
| Formal | **PASS** (proofs; predictor not established) | `sh tools/formal_check.sh` |
| Co-simulation | **PASS**, 11 of 11 injected faults detected | `python3 tools/cosim_host_rtl.py`; `python3 tools/cosim_negative_controls.py` |
| Python tests | **PASS**: 74 tests | `python3 -W error::ResourceWarning -m unittest discover -s tests` (inside `sh sim/run_all.sh`) |
| CDC, lint, synthesis | **PASS** | `python3 tools/cdc_check.py`; `sh tools/lint_synth.sh` |
| Reproducibility | **PASS**: artifacts, experiments, validations byte-identical | `python3 tools/check_artifacts.py`; `sh tools/check_experiments.sh`; `sh tools/check_validation.sh` |
| Traceability | **PASS** | `python3 tools/check_traceability.py` |
| Whole pipeline | **PASS** (exit 0) | `sh sim/run_all.sh` |
| ADC timing (simulation only) | with synchroniser 20 ns / without 60 ns; **hazard OPEN** | `python3 tools/adc_timing_sweep.py` |
| Physical hardware | **BLOCKED**, 0 % | no hardware evidence exists |

### What percentage is complete? (after the correction phase)

| Dimension | Original audit | **Now** |
|---|---|---|
| Implementation | about 76 % | **76.5 %** |
| Simulation testing | about 77 % | **76.8 %** |
| Independent verification (strict, capped, all evidence internal) | about 26 % | **31.4 %** |
| Hardware validation | 0 % | **0 %** |

(`python3 tools/completion_score.py --table`; the verification figure rises because the formal check is now a real proof, the co-simulation is checked against an independent reference with fault conditions and negative controls, the CDC check covers every boundary input and weak kills were strengthened. It remains capped because nothing has outside review.)

### Recommendation after the correction phase

**Ready for external code review and for a CI push, for the simulation scope. Not hardware-ready.**
Conditions a reviewer should be told up front, all documented: H-16 (the MISO structure decision is pending and the real ADC timing is unverified); the e-stop acts only through the FPGA; pins are unverified (24 of 41 bits unassigned); the slope predictor is not formally established; the demo video is stale; the paper's references have not been re-verified or read; CI has never run. Hardware validation remains 0 % and nothing here claims otherwise.

---

# Original audit (before the correction phase; kept unchanged, superseded where noted above)

## 0. Method and constraints

* Every verification command ran in a **scratch copy** of the tree (`$A/tree`, where `A=/tmp/claude-0/-home-user-tactile-reflex-system/9b6cb197-2d64-5301-8a19-d5cb01423396/scratchpad/audit`). The scratch copy was made with `tar --exclude=./.git -cf - . | tar -xf - -C $A/tree`.
* No RTL, testbench, tool, documentation, branch or Git history was modified. This report is the only file added.
* **Disclosure (one slip):** an early ADC-delay sweep ran `vvp` with the repository as its working directory, and `tb_top` unconditionally opens `results/trace_override.csv` and `results/trace_estop.csv` for writing. Both files were rewritten at 10:49:54 UTC. Their **content is byte-identical** (SHA-256 still matches the backup manifest; `git status` shows no change), only the modification time differs. All later runs used the scratch copy. The sweep that caused this is documented in 11 below.
* The independent scripts are not in the repository (that would modify `tools/`). They are in `$A`: `indep_mut.py`, `indep_mut.json`, `misotest` (sweep commands in section 11), `model_dly.v`, `top_nosync.v`.
* "Independent" here means: I re-derived each result myself rather than trusting the earlier reports. It is the same author's toolchain and the same testbenches, not outside review. This limits how far the verification percentage can go.

## 1. Verdict table

| # | Area | Result | One-line reason |
|---|---|---|---|
| 1 | 47-mutant campaign and audit | **PASS** | re-run independently: 47/47 killed, 0 invalid, 0 compile errors, every kill has failed-assertion evidence; 17 kills are thin (see 2.1) |
| 2 | 18 testbenches / 4,236 assertions | **PASS** (with a reporting defect) | identical summary reproduced; but 3,776 of the 4,236 are per-vector replay evaluations and one testbench mislabels its vectors (D-4) |
| 3 | Safety monitor and injected faults | **PASS** | no violation on the RTL; flags M42 to M47 (the five originally injected M42 to M46, plus M47) |
| 4 | Bounded formal, incl. negative controls | **PASS as executed; FAIL as documented** | runs and the two controls are refuted, but it refutes only 11 of 19 governor/PWM mutants and is vacuous for the PWM kill (D-2) |
| 5 | Host-to-RTL co-simulation, 86 frames | **PASS** (limited coverage) | real host code against real RTL; my own stronger check passes 47/47; but only 10 over-limit and 7 e-stop frames, open loop (D-5) |
| 6 | 60 Python tests, JSON model | **PASS** | 60/60; model identical to a fresh scikit-learn retrain on 293,600 vectors |
| 7 | CDC, lint, synthesis, regression scripts | **PASS** (limitations) | all pass and fail on broken copies; CDC checks a fixed list of 5 inputs only (D-6) |
| 8 | Completion percentage and tracker | **PASS arithmetic; two scores overstated** | recomputed identical; adjusted estimate slightly lower (section 9) |
| 9 | Final backup | **PASS** | checksum, extraction and live-tree comparison all clean; nothing omitted |
| 10a | README | **PASS** with open items | no hardware claim; states pins unverified |
| 10b | Paper | **PASS with defects** | numbers verified; formal wording overstates; omits the MISO hazard (D-1, D-2) |
| 10c | Deck / review script | **PASS with open items** | stale counts corrected; "Latency-Optimal" and slide 9 ratings flagged, not changed |
| 10d | Video | **STALE (documented)** | still says 175 checks / 12 testbenches; pinned to a snapshot; not re-rendered |
| 11 | MISO synchroniser timing hazard | **FAIL (unresolved)** | confirmed and quantified; larger than documented (D-1) |
| 12 | Omitted generated/untracked files | **PASS** | none omitted |
| 13 | Changes not in the changelog | **PASS** (minor gaps) | no undocumented functional change (D-9) |
| 14 | Physical hardware readiness | **BLOCKED** | no board, sensor, driver or motor evidence; 0 % |

## 2. Findings by area

### 2.1 Mutation campaign (PASS)

```bash
cd $A/tree
python3 $A/indep_mut.py $A/tree $A/indep_mut.json          # my own driver: applies each edit, runs the full regression with --no-strict-warnings, records failing testbenches, FAIL lines, timeouts
```
Result (`$A/indep_mut.json`): 47 killed, 0 survived, 0 bad patterns, 0 compile errors, **agrees mutant-by-mutant with `results/mutation_report.json`**; each edit changes at most 2 lines (the earlier audit said "at most 4": not wrong, just loose). 46 of 47 kills print explicit `FAIL ...` text; M12 has 0 `FAIL` lines but 5 failed assertions in `tb_pred_governor`'s summary. No kill relies only on a timeout or a compile problem (4 mutants also time out, but each also has failed assertions).
Are the kills meaningful? By inspection of the failing messages, yes: each mutant fails assertions that name the behaviour it breaks (e.g. M13/M42 PWM kill in `tb_pwm_generator` and the monitor's S2; M45 "AI can raise the command" in `tb_safety_governor`, `tb_replay` and S5; M40 only in `tb_reset_recovery`'s 3 ns reset scenario).
Caveats: 17 mutants are caught by exactly one testbench (M01, M06, M07, M11, M12, M14, M17, M23, M25, M26, M27, M28, M34, M35, M38, M40, M41) and six of them (M06, M11, M17, M25, M40, M41) by **a single assertion**. Those kills are real but fragile. The mutants are hand-written single edits made by the same author who wrote the tests; a 100 % score measures sensitivity to those faults only. The committed `results/mutation_audit.json` and my run agree, but share the testbenches, so this is reproducibility, not an independent oracle.

### 2.2 Regression: 18 testbenches, 4,236 assertions (PASS, reporting defect)

```bash
cd $A/tree && python3 tools/run_regression.py --json ../reg_indep.json --log ../reg_indep.log
```
`18 testbenches, 18 passed, 0 failed; assertions passed=4236 failed=0`; my JSON equals `results/regression_summary.json`. Composition: **460 directed assertions + 2 x 1,888 replay invariant evaluations (3,776)**. Quoting "4,236 assertions" as test points overstates the directed coverage; the deck correctly says 460. I read the diffs of the 11 original testbenches (`git diff -U0 -- tb`): they add only the summary suffix, the safety monitor instances/checks and the `DEBOUNCE_CLKS(4)` parameter the new debouncer needs. No assertion was removed or loosened.
Defect D-4: `tb_pred_governor` prints `VECTORS 0 NOTE directed assertions only` and counts 1 assertion, although it compares the RTL with a reference on 4,720 vectors (`results/sim_log.txt`: `pred_rtl_vs_model vectors=4720`).

### 2.3 Safety monitor and injected faults (PASS)

From `$A/indep_mut.json`: the monitor invariants fire on M03, M04, M05, M09, M10, M13, M42, M43, M44, M45, M46, M47. The six safety-specific mutants M42 to M47 are all flagged (the five originally reported, M42 to M46, plus M47 for S6). Each also fails non-monitor assertions, so the monitor adds redundancy rather than being the only detector. No violation on the real RTL (it is inside the 4,236).

### 2.4 Bounded formal (PASS as executed; documentation overclaims: D-2)

```bash
cd $A/tree && sh tools/formal_check.sh      # FORMAL PASS x2 (PRED_EN 0 and 1), negative controls n1, n2 "correctly refuted (counterexample found)"
```
I also ran **every governor/PWM mutant through the same formal harness** (script in my session; 19 mutants, both predictor settings). Result: **11 of 19 refuted**. Refuted: M01, M03, M04, M05, M09, M10, M43, M44, M45, M46, M47. **Not refuted: M02 (hysteresis), M06, M07 (predictive trip), M08 (class-2 cap), M11, M12, and both PWM-kill mutants M13 and M42.**
Why the PWM kill is not covered: `pwm_generator` latches a new duty only when its 12-bit counter wraps (4,096 clocks). Within 14 clocks of reset `duty_active` is 0, so `pwm_out` is 0 whether or not `kill` works, and property P2 ("PWM low one clock after safe state") is **vacuous at this depth**. `HAZARD_ANALYSIS.md` R-03 lists "SIM + BOUNDED", and `paper/paper.md` section 5.4 and `VERIFICATION_REPORT.md` section 4 describe the properties as covering "the governor and PWM stage"; the PWM part of that is supported by simulation and the monitor only. P1, P3 to P6 are meaningful (they refute the mutants listed above). Hysteresis (R-02), the predictor (R-13) and the exact AI caps are not formally covered, and the documents already list them as SIM only.

### 2.5 Host-to-RTL co-simulation (PASS, limited)

```bash
cd $A/tree && python3 tools/cosim_host_rtl.py     # PASS; 86 telemetry frames, 85 decoded (the last needs the next header), 0 dropped, stable frames checked A/B/C = 68
```
To test whether this is more than "generated packets passing", I wrapped its internals and recomputed, per frame, the cap the real model's class should produce: for the real-model pass, on all **47 stable AI-valid frames, command == min(LUT, cap[class]) with classes 0, 1, 2 and 3 all present** (12/2/26/7 frames); adversarial pass 47/47. So the RTL behaves correctly, and the host genuinely feeds on the RTL's own telemetry (the classes come from features computed on the bytes the RTL transmitted). 84 of 86 frames were AI-valid.
Limits (D-5): the harness itself only asserts `cmd <= LUT` for the real model (exact caps only for the adversarial pass); only **10 over-limit and 7 e-stop stable frames** per pass are exercised; the AI answers open loop, one packet per frame, never reacting to the safe state; the model was trained on 500 us samples but sees features at an 80 us telemetry cadence, so its classes are not meaningful grasp classes; the UART is ideal and the ADC behavioural. It tests protocol, parser and limit behaviour, not AI quality or any real-time effect. The "86 frames" figure is frames transmitted; 68 per pass were stable enough to assert on.

### 2.6 Python tests and JSON model (PASS)

```bash
cd $A/tree && python3 -W error::ResourceWarning -m unittest discover -s tests      # Ran 60 tests ... OK
# model: fresh sklearn retrain (max_depth=4, random_state=0) vs results/tree.json
```
Structure (children, features, thresholds) identical to the fresh retrain; 0 mismatches on all 240,000 samples, **3,600 vectors placed at every internal threshold at float32 and float64 resolution**, and 50,000 wide-range random vectors. No pickle in the JSON or in runtime code.

### 2.7 CDC, lint, synthesis, regression scripts (PASS, limitations)

```bash
python3 tools/cdc_check.py; sh tools/lint_synth.sh; sh tools/formal_check.sh; python3 tools/check_pins.py; python3 tools/check_wokwi.py; python3 tools/check_traceability.py      # all in $A/tree
```
All pass. Negative controls reproduced: removing the MISO synchroniser is flagged by `cdc_check.py` (2 violations); an injected latch is flagged by `lint_synth.sh`. Findings: **D-6** `cdc_check.py` validates a hard-coded list of five inputs, so a *new* asynchronous input captured with no synchroniser (I added a raw `KEY[2]` register to a copy) passes. **D-7** `tools/make_quartus_project.py` creates its output directory before validating the pins, leaving an empty git-ignored `quartus_build/` after a refused run (present in the live tree, harmless). Synthesis numbers are generic Yosys (about 625 LUT4, 466 flip-flops), not a Quartus fit; no timing exists.

### 2.8 Completion percentage and tracker (PASS arithmetic)

The 32-row inventory in `results/completion_score.json` recomputes to the stored values (86.8 / 77.6 / 76.8 / 28.5 / 0.0) and the task mean to 85.0. Two scores are generous given the findings above: PWM "verified" 0.75 relies on a formal property that is vacuous (should be 0.5); the ADC interface and board top are credited as implemented/verified although the first-bit timing hazard (section 11) is open; and the formal credit overall is partial (11 of 19). My adjusted estimate is in section 9.

### 2.9 Final backup (PASS)

```bash
B=.../scratchpad/backups_exec; TS=$(cat $B/final_ts.txt)
sha256sum -c $B/final_$TS.tar.gz.sha256            # OK;   baseline_20261106T0838Z.tar.gz.sha256 also still OK
tar xzf $B/final_$TS.tar.gz -C $A/bk; diff -rq $A/bk /home/user/tactile-reflex-system --exclude=.git     # only difference: the empty quartus_build/
sha256sum -c $B/final_$TS.manifest.sha256          # no mismatch (498 files)
cmp $B/final_$TS.bundle $B/baseline_20261106T0838Z.bundle     # identical => no commit was made
```
The tarball excludes only `.git` and the empty `quartus_build/`; git-ignored files (`results/tree.pkl`, `sim/build`, caches, build products) and all untracked directories are present. The extracted copy ran the full regression and host tests earlier. Observations: the backup predates this report (so it does not contain it); the git bundle holds only HEAD, so **all uncommitted work exists only in the tarball** (plus `final_*.tracked_changes.diff` for tracked files). Anything committed later should be re-backed-up.

### 2.10 Documents

* **README**: states simulation-only and unverified pins; no hardware claim. Open: the title still says "Latency-Optimal" (unsupported superlative).
* **Paper**: numbers re-checked against the result files (18/4236, 47, 0.926 +/- 0.008, 625/466, 25 tests, 13/839). Defects: section 5.4 wording on formal (D-2); section 6.4 does not mention the MISO timing hazard (D-1); references: metadata not re-verified, no full text read (stated).
* **Deck / review script**: corrected counts verified (slide 12: 460 over 16 testbenches). Remaining: slide 1 "Latency-Optimal"; slide 9 DRV8871 ratings (6.5 to 45 V, 3.6 A) could not be checked against a datasheet.
* **Video**: still says "All 175 directed checks across 12 testbenches" (caption line 127). Its claims check passes only against a pinned snapshot (`demo_video/evidence_snapshot/sim_log_at_render.txt`). It is stale relative to the repository and says nothing false about hardware.

## 3. The MISO synchroniser: an unresolved ADC timing hazard (FAIL, D-1)

Question asked: does the synchroniser added in `rtl/tactile_reflex_top.v` introduce an unresolved ADC timing hazard? **Yes, and it is worse than `HAZARD_ANALYSIS.md` H-16 states.**
H-16 and the RTL comment ("well inside the bit window") describe the loss as 6 -> 4 clocks (120 -> 80 ns). The first data bit is different: `adc_interface` raises SCLK's first falling edge only 3 clocks after chip-select falls and samples the previous bit there, so with the synchroniser the leading bit is sampled **1 clock (20 ns) after CS falls**, versus 3 clocks (60 ns) before.
Measured by adding a programmable output delay to the ADC model in a scratch copy and running `tb_top` (the delayed model: `#(DLY)` before each `miso` update; sweeps in `$A`):

| Variant | Passes at ADC output delay | Fails from |
|---|---|---|
| With synchroniser (current RTL) | 0 ns, 20 ns | **22 ns** (3 checks fail; timeouts from 81 ns) |
| Without synchroniser (the original wiring) | up to 60 ns | 62 ns |

The three failing checks are "ADC frame error: invalid ADC trips safe state", "persistent invalid ADC latches sensor fault", "fault stays latched after the ADC recovers": the leading bit is mis-sampled, so a **frame-error indication is missed or invented**; the 12 data bits keep about 80 ns of margin. The failure direction for a mis-read leading bit on a healthy part is a spurious frame error (fail-safe, availability loss); a stuck-high data line would still read as high. Whether the real AD7476A's CS-to-first-bit delay (and board and pin delays) fits in 20 ns is unknown: the datasheet could not be obtained and no scope measurement exists. I do not claim it fails or passes. It is a hardware-readiness blocker and a documentation contradiction; the simulation cannot settle it because the model has zero delay.
Options (all need approval): drop the synchroniser (SCLK is generated by the FPGA, so MISO is synchronous to it, which removes the first-bit penalty), keep a one-stage register, or retime the first sample; then add a delayed-ADC-model testbench so this is covered.

## 4. Remaining defects and contradictions (nothing fixed, per instructions)

| ID | Severity | Where | Issue |
|---|---|---|---|
| D-1 | High for hardware, Medium for review | `rtl/tactile_reflex_top.v` comment; `HAZARD_ANALYSIS.md` H-16; `CHANGELOG_IMPLEMENTATION.md`; `FINAL_PROJECT_AUDIT.md`; paper 6.4 | MISO margin understated; first-bit margin is 20 ns not 80 ns (section 3) |
| D-2 | Medium | `HAZARD_ANALYSIS.md` R-03 (and R-07, "BOUNDED"), `VERIFICATION_REPORT.md` sec. 4, `paper.md` 5.4 | formal check is vacuous for the PWM kill and covers 11/19 governor/PWM mutants; claim "SIM + BOUNDED" for R-03 is wrong (SIM + monitor only) |
| D-3 | Low | README, paper, tracker | "4,236 assertions" conflates 460 directed with 3,776 replay evaluations |
| D-4 | Low | `tb/tb_pred_governor.v` | reports `VECTORS 0` and 1 assertion for a 4,720-vector comparison |
| D-5 | Low | `tools/cosim_host_rtl.py` | asserts less than the RTL does (no exact caps for the real model); thin over-limit/e-stop coverage; open loop |
| D-6 | Low | `tools/cdc_check.py` | fixed input list; an unlisted unsynchronised input passes |
| D-7 | Trivial | `tools/make_quartus_project.py` | creates directory before validating; empty `quartus_build/` in the tree |
| D-8 | Low | `results/mutation_audit.json` text | "at most 4 changed lines" (actual 2); 17 single-testbench kills, 6 single-assertion kills (fragile) |
| D-9 | Trivial | `CHANGELOG_IMPLEMENTATION.md` | does not name: the 11 modified original testbenches, `tools/gen_host_link_vectors.py`, `tb/host_link_*.mem`, regenerated `results/sim_log.txt` and `sim_console.png`, new `results/*.json`, or say that `experiments/`, `paper/` (apart from `paper.md`) and `demo_video/` are earlier untracked work left unchanged |
| D-10 | Trivial | live tree | this audit touched the modification time of two trace CSVs (content unchanged) |
| D-11 | Medium | video, deck title, slide 9 | stale/unsupported statements remain (listed in 2.10); all disclosed |
| D-12 | Medium | repository state | all work is uncommitted; the only full copy is the tarball (bundle is HEAD only) |

No test was found to be weakened, no hard-coded output was found, and no contradiction was found between the result files and the reports apart from D-1, D-2 and D-3.

## 5. Simulation readiness versus hardware readiness

**Simulation readiness: good, with the defects above.** The RTL passes an 18-testbench regression, a reproducible 47-mutant campaign (independently re-run), a cycle-accurate monitor, a bounded formal check (with the coverage limits stated), a structural CDC check, lint/synthesis checks, a host-in-the-loop co-simulation and 60 software tests; derived artifacts regenerate byte-identically.
**Hardware readiness: not ready, 0 % validated.** Nothing has run on a board. Open items that block a first supervised bench test: unverified pins (24 of 41 port bits unassigned), no Quartus build or timing, the MISO first-bit hazard (section 3), the FPGA-only e-stop (H-03), configuration-time pin state (H-04), stuck PWM (H-05), uncalibrated thresholds, no real sensor or ADC data. See `HARDWARE_VALIDATION_GUIDE.md` (every stage BLOCKED).

## 6. Actions requiring your approval

1. Correct the documents: H-16 and the RTL comment (D-1), R-03/R-07 and the formal wording in `VERIFICATION_REPORT.md` and the paper (D-2), the assertion-count wording (D-3), and add the missing changelog entries (D-9).
2. Decide the MISO fix (section 3) and approve an RTL change plus a delayed-ADC testbench.
3. Strengthen verification (optional): a PWM kill property that is not vacuous (e.g. a small `PWM` period parameter or a longer bound), exact-cap assertions in the co-simulation, more over-limit/e-stop frames, `tb_pred_governor` vector count, a CDC checker that scans every port (D-4 to D-6).
4. Commit the work to a branch and push it so CI can run (the CI workflow has never run); re-take the backup afterwards.
5. Re-render the video, rename "Latency-Optimal", verify slide 9 ratings (D-11).
6. Allow the blocked hosts (`terasic.com.tw`, `ti.com`, `intel.com`, DOI/Crossref) or supply the files, to unblock pins, datasheets and references.
7. Choose whether to delete the empty `quartus_build/` (I did not).
8. Any hardware work, and the hardware e-stop design decision.

## 7. Commands used (all inside `$A/tree` unless stated)

```bash
git rev-parse HEAD; git status --short -uall; git diff -U0 -- tb; git diff -U2 -- rtl      # live, read-only
sha256sum -c $B/final_$TS.manifest.sha256; diff -rq $A/bk /home/user/tactile-reflex-system --exclude=.git
python3 $A/indep_mut.py $A/tree $A/indep_mut.json
python3 tools/run_regression.py --json ../reg_indep.json --log ../reg_indep.log
sh tools/formal_check.sh      # plus a loop applying each safety_governor/pwm_generator mutant to the formal harness
python3 tools/cosim_host_rtl.py   # plus a wrapper recomputing min(LUT, cap[class]) per frame
python3 -W error::ResourceWarning -m unittest discover -s tests
python3 tools/cdc_check.py; sh tools/lint_synth.sh; python3 tools/check_pins.py; python3 tools/check_wokwi.py; python3 tools/check_traceability.py
# MISO: model_dly.v (adds #(DLY) before each miso update), tb_top with .DLY(...), RTL with and without ms[1], delays 0..119 ns
```

## What percentage is complete? (original audit; superseded by the table above)

Independent re-derivation (inventory recomputed from `results/completion_score.json`, then reduced for this audit's findings: vacuous PWM formal property, partial formal coverage, the open ADC first-bit hazard):

| Dimension | Tracker | **This audit** |
|---|---|---|
| Implementation (does what it should, in simulation/host) | 77.6 % | **about 76 %** |
| Simulation testing (automated tests exist and pass) | 76.8 % | **about 77 %** |
| Independent verification (strict; all evidence produced inside the project, no outside review) | 28.5 % | **about 26 %** |
| Hardware validation | 0 % | **0 %** |

Code/documents written: about 87 %. The hardware-bound and external-document-bound items (pins, Quartus, bring-up, calibration, real data, Wokwi, hardware e-stop) are what keep the first three numbers below 80 %.

## Final recommendation (original audit; superseded by the recommendation above)

**Ready for CI push, but not hardware.**

The simulation work is solid, reproducible and honestly bounded, so pushing it to a branch to let CI run is low-risk and useful. I would **not** yet send it for external code review until the documents are corrected (D-1 and D-2: the MISO hazard is understated and the formal claim for the PWM kill is not supported), because a reviewer would find both quickly. The project is **not hardware-ready**: no physical validation evidence exists, and the MISO first-bit hazard, the FPGA-only e-stop and the unverified pins must be resolved before any bench test.
