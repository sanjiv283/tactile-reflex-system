#!/bin/sh
# Re-run the frame-granular and step-expansion model-vs-RTL validations on the CURRENT rtl/ in a temporary copy; compare with the stored results.
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -r experiments rtl tb "$T"/
( cd "$T" && python3 experiments/validation/run_validation_v2.py >/dev/null && python3 experiments/validation/step_expansion_check_v2.py >/dev/null )
rc=0
for f in frame_summary.md frame_mismatches.json step_expansion_result.json frame_rtl_log.txt frame_model_log.txt; do
  if cmp -s "$T/experiments/validation/results_v2/$f" "experiments/validation/results_v2/$f"; then echo "IDENTICAL experiments/validation/results_v2/$f"; else echo "DIFFERENT  experiments/validation/results_v2/$f"; rc=1; fi
done
[ $rc -eq 0 ] && echo "VALIDATION REPRODUCES on the current RTL"
exit $rc
