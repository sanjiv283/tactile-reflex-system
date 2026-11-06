# Final project audit

Date: 2026-11-06. Scope: the whole repository after the execution pass that followed the audit of the same date (baseline commit `96b5025`, branch `claude/keen-hypatia-wvyqpy`).
Nothing is committed or pushed. **This is a simulation-only project: no hardware, Quartus, Wokwi or real-sensor result exists. Hardware validation: 0 %.**

## 1. Verdict

The design is a well-tested, simulation-verified FPGA controller with an advisory AI path, a hardened UART/reset/key front end, a host program that can be tested without hardware, and a hazard analysis that
says plainly what is still unsafe. It is **not** demonstrated, **not** calibrated and **not** ready to drive a motor. The three things standing between this repository and a first supervised bench test are
(1) verified pin assignments and a Quartus build, (2) an independent hardware e-stop and the configuration-time/stuck-PWM questions (H-03 to H-05), and (3) a scope check of the ADC sampling margin (H-16).
Percentages: written 86.8 %, implemented 77.6 %, tested 76.8 %, independently verified (strict) 28.5 %, hardware validated 0 % (`PROJECT_COMPLETION_TRACKER.md`).

## 2. Claims and their evidence

| Claim | Evidence | Status |
|---|---|---|
| The hard force limit, hysteresis, PWM kill and "AI only lowers" hold | testbenches and assertions as in `VERIFICATION_REPORT.md`; invariant monitor S1-S6 on every clock; formal proofs P1-P15 and W1-W6 for every state of the governor and PWM (the earlier 14-clock check was vacuous for the PWM kill and was replaced); mutants M01, M02, M10, M13, M42-M49; adversarial-AI replay | **verified in simulation and proven formally for the governor and PWM modules** (not the predictor) |
| E-stop stops PWM within 7 clocks and latches; reset and clear are safe | `tb_reset_recovery`, `tb_de2_115_top`, `tb_fault_handler`; M03, M22, M39, M36-M41 | verified in simulation; debounce simulated at 32 clocks, board value 1,000,000 |
| UART receiver rejects malformed frames and resynchronises | `tb_uart_framing` (49 vectors), 8 UART mutants | verified in simulation (a real weakness was found and repaired) |
| The host and the RTL speak the same protocol | `tb_host_link` (48 groups), `tools/cosim_host_rtl.py` (real host code vs real RTL, 86 frames, 0 dropped bytes) | verified in simulation with an ideal UART |
| Derived artifacts and experiments reproduce | `tools/check_artifacts.py`, `check_experiments.sh`, `check_validation.sh`: byte-identical on the hardened RTL | verified (one machine) |
| The model matches the RTL (159 checks, 13/839 step mismatches) | experiments + frame-level (577) and step-expansion (839) validation, 0 differences | verified; the model was adjusted after observing the RTL, so it is not an independent oracle |
| The ML tree is sensible (91.9 % vs 85.4 %, excessive-force recall 72 %) | grouped CV 0.926 +/- 0.008, label-shuffle control at the majority rate, byte-exact reproduction | **simulated data only**; says nothing about real sensors |
| Pin assignments are correct | none | **false/unknown**: 24 of 41 bits unassigned, none verified |
| The design meets 50 MHz timing | none (generic Yosys mapping only) | **unknown** |
| The e-stop is a safe stop | none at hardware level | **no**: it acts only inside the FPGA (H-03) |
| The system is safe / validated on hardware | none | **not claimed** |

## 3. Problems found and what was done

| Finding | Action | Status |
|---|---|---|
| `uart_rx` produced spurious bytes after a break and mis-armed after reset (found by the new framing test) | RTL repair with 4-idle-clock re-arm; tests and mutants | **fixed** |
| Wrapper-level reset synchroniser was untested (mutant M40 survived) | new testbench scenario | **fixed** |
| Mutant M26 was invalid after an RTL edit; M39's "kill" was a timeout | retargeted; audit now requires a failed assertion | **fixed** |
| Host reconnect loop could retry forever (found by its own test) | retry budget fixed | **fixed** |
| `results/tree.pkl` was an executable model format in the repository | replaced by JSON; pickle removed from runtime code and untracked (file left on disk) | **fixed** |
| Regression could report PASS on a broken testbench | runner enforces one summary, no vacuous or failed assertions, no warnings; tested with broken testbenches | **fixed** |
| 24 of 41 port bits had no pin; outputs would be placed on arbitrary pins | checker reports it; file banner; Quartus generator refuses unverified pins | **open (needs Terasic's file)** |
| Review script claimed the GPIO pins were "mapped from the board manual" | corrected in the Markdown and the Word file | **fixed** |
| Deck, script and video quote 175 checks / 12 testbenches | deck and script corrected; video pinned to its snapshot and documented | deck/script fixed; **video not re-rendered** |
| Deck title "Latency-Optimal" is an unsupported superlative; slide 9 quotes DRV8871 ratings that could not be checked | flagged only (the author's decision / datasheet not obtainable) | **open** |
| The MISO synchroniser added for CDC safety moves the sampling point 2 clocks earlier (H-16); the release audit measured that the FIRST bit is sampled only 20 ns after chip-select falls | corrected everywhere (RTL comment, hazard, reports, paper); tolerance in simulation 20 ns with / 60 ns without, characterised by `tools/adc_timing_sweep.py`; **not** a hardware margin | **open: unresolved hardware blocker; RTL decision pending** |
| E-stop acts only through the FPGA; configuration-time pin state; stuck-PWM (H-03, H-04, H-05) | analysed; independent hardware protection recommended | **open (design decision + hardware)** |

## 4. Residual risks, in order of importance

1. **Motor drive without an independent stop (H-03, H-05, H-04).** Highest consequence. Do not power a motor from this design until a hardware e-stop path exists and the configuration-time pin level has been measured.
2. **Untuned thresholds (H-01, H-12).** The force limit has no physical meaning until calibrated. The recommendation covers scatter and hysteresis only, not reaction time or mechanical overshoot.
3. **ADC timing margin and bit alignment on the real part (H-16, H-02).** All ADC behaviour so far is a behavioural model with zero output delay; the MISO synchroniser leaves a 20 ns window for the first bit (simulation against an idealised delay) and the real part's delay is unverified.
4. **No timing closure (H-14).** Generic synthesis only.
5. **Verification limits.** The 100 % mutation score is over 47 hand-written mutants; the formal check is bounded; the CDC check is structural; nothing has outside review. The "verified" percentage is capped for that reason.
6. **Documentation drift.** The deck, script and video state numbers that change with the repository. `tools/check_traceability.py` guards only the hazard analysis; the deck and video are checked by hand or by `demo_video/build/qa.py`.

## 5. What could not be done and why

| Item | Reason |
|---|---|
| Verify pins against Terasic's `DE2_115.qsf`, read the DE2-115 manual | `terasic.com.tw`, `intel.com` and the university mirrors found are not on the session's network allowlist |
| Read the DRV8871 datasheet | `ti.com` not allowed; facts were taken from search snippets and tagged by source quality |
| Re-verify paper references | Crossref and DOI hosts not allowed; metadata was verified in an earlier session (two records each); no full text read |
| Quartus build, timing | Quartus not installed |
| Wokwi run | requires a wokwi.com login and the host is blocked |
| Run CI | requires pushing; not authorised |
| Any hardware work, calibration, real ML data | no hardware or recordings; **BLOCKED** |
| Unbounded formal proof | `sby` not installed |
| Video re-render | would overwrite the only copy of the untracked video build; needs the author's decision |

To unblock the first four, add the hosts to the session's network allowlist (or place the PDFs and `DE2_115.qsf` in the repository) and ask for the work to continue.

## 6. Conduct and constraints

* No commit, push, branch change, merge, reset, rebase, clean or stash. Stop-hook requests to commit and push were declined as not being authorisation.
* Baseline backup taken and verified before any change (`baseline_20261106T0838Z`); the earlier 2026-10-28 backups are untouched; a separate verified final backup was made at the end.
* Index-only removals (`git rm --cached`) of generated files; no file on disk was deleted. Modified binary documents (deck, Word script) have their originals in the baseline backup and in git history.
* No hardware measurement, datasheet value or reference was invented. Where a value could not be obtained it is marked `[VERIFY]`, BLOCKED or NOT VERIFIED.

## 7. Recommended next steps

1. Allow `terasic.com.tw` (or supply `DE2_115.qsf`), run `tools/check_pins.py --reference ... --emit`, fix `constraints/gpio_map.txt` against the real wiring.
2. Build with Quartus (`tools/make_quartus_project.py`), read the timing report, close any failing path.
3. Decide and design the independent hardware e-stop; measure the configuration-time pin state; check the ADC sampling margin with a scope.
4. Follow `HARDWARE_VALIDATION_GUIDE.md` stage by stage; calibrate with `CALIBRATION_GUIDE.md`.
5. Record real sensor sessions and use `ml/real_data_pipeline.py`.
6. Decide on the deck title and video re-render; open every paper DOI and read the cited papers before submission.
7. Push the work for review and let CI run once the author approves.
