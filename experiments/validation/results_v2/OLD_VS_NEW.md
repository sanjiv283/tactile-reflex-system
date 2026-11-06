# Old (WD_STEPS=2) vs new (time-based watchdog) — comparison record, 2026-10-28
Applied: experiments/validation/watchdog/proposed_time_based_watchdog.diff (sha256 09e65a47...) to experiments/wokwi/reflex_model.h and scenarios.h.
Preserved original model: experiments/wokwi_v1_wd2/ (reproduces experiments/results/model_log.txt byte-for-byte). Original outputs untouched:
experiments/results/, experiments/validation/results/, experiments/validation/watchdog/results/, experiments/wokwi_single/.

## model_log.txt old -> new (8 differing lines, 4 entries)
- PARAM: `WD_STEPS=2` -> `WD_CLK=2000,FRAME_CLK=104,SLOT_CLK=25000`
- LOG S06c_dropout step 21: safe 0,cmd 157,trip 0 -> safe 1,cmd 0,trip 2, event safe_on
- LOG S06c_dropout step 22: event safe_on -> (empty); values unchanged (safe 1,cmd 0,trip 2)
- SUM S06c_dropout: first_safe 1 -> 0 (checks 13/13 unchanged)
No other model_log line differs.

## Other outputs old -> new
- rtl_log.txt, rtl_single_invalid.txt, checks.csv: identical.  All six validation/results files: identical.
- dataset.jsonl: every record differs only in `parameters` (embedded WD fields); S06c additionally model_first_safe_step 1->0 and model_vs_rtl_mismatches 1->0.
- summary.md: S06c mismatches 1/40 -> 0/40; TOTAL 14/839 -> 13/839.

## Remaining step-level model-vs-RTL mismatches (13/839) — NOT resolved
S06a_one_invalid steps 21-27 (7), S06b_persist_invalid steps 21-23 (3), S06d_rail steps 21-23 (3). Cause (tested, not assumed): one model step = 1 sample, one RTL step ~240 ADC frames.
Frame-level (577 frames) and step-expansion (839 steps) checks show 0 differences; they explain but do not remove these step-level differences.
