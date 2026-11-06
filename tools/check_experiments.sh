#!/bin/sh
# Re-run the v2 experiment pipeline (software model vs RTL replay) on the CURRENT rtl/ in a temporary copy and compare every deterministic output
# with experiments/results_v2/. The committed evidence is never touched. Exit 1 if anything differs.
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -r experiments rtl tb "$T"/
( cd "$T" && sh experiments/run_experiments_v2.sh >/dev/null )
rc=0
for f in model_log.txt rtl_log.txt checks.csv summary.md rtl_single_invalid.txt; do
  if cmp -s "$T/experiments/results_v2/$f" "experiments/results_v2/$f"; then echo "IDENTICAL experiments/results_v2/$f"; else echo "DIFFERENT  experiments/results_v2/$f"; diff "$T/experiments/results_v2/$f" "experiments/results_v2/$f" | head -5; rc=1; fi
done
[ $rc -eq 0 ] && echo "EXPERIMENTS REPRODUCE on the current RTL"
exit $rc
