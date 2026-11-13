#!/bin/sh
# ADC_GAP guard check: valid settings must elaborate and run, invalid ones must FAIL to elaborate (non-zero exit, error names the rule).
# Works in a temp dir; writes nothing into the repository. Run from anywhere.
cd "$(dirname "$0")/.."
T=$(mktemp -d); rc=0
run() {  # gap idle expect(ok|reject)
  out=$(iverilog -g2005 -Ptb_adc_gap_guard.GAP=$1 -Ptb_adc_gap_guard.IDLE=$2 -o $T/g.vvp tb/ad7476_model.v tb/tb_adc_gap_guard.v rtl/adc_interface.v 2>&1); c=$?
  if [ "$3" = ok ]; then
    if [ $c -eq 0 ] && vvp $T/g.vvp | grep -q "PASS 2 FAIL 0"; then echo "OK   gap=$1 idle_chk=$2 accepted"; else echo "FAIL gap=$1 idle_chk=$2 should be accepted"; rc=1; fi
  else
    if [ $c -ne 0 ] && echo "$out" | grep -q "ERROR_adc_interface_GAP_must_be"; then echo "OK   gap=$1 idle_chk=$2 rejected (elaboration error)"; else echo "FAIL gap=$1 idle_chk=$2 should be rejected"; rc=1; fi
  fi
}
run 8 0 ok; run 63 1 reject; run 64 1 ok; run 256 0 ok; run 257 0 reject; run 0 0 reject; run 256 1 ok; run 63 0 ok; run 1 0 ok; run 257 1 reject; run 0 1 reject
# same rejection through the whole design in Yosys (the synthesis front end)
for cfg in "257 0" "63 1" "0 0"; do set -- $cfg
  if yosys -q -p "read_verilog rtl/*.v; chparam -set ADC_GAP $1 -set IDLE_CHK $2 de2_115_top; hierarchy -check -top de2_115_top" >/dev/null 2>&1; then echo "FAIL yosys gap=$1 idle_chk=$2 should be rejected"; rc=1; else echo "OK   yosys gap=$1 idle_chk=$2 rejected"; fi
done
for cfg in "8 0" "64 1" "256 0"; do set -- $cfg
  if yosys -q -p "read_verilog rtl/*.v; chparam -set ADC_GAP $1 -set IDLE_CHK $2 de2_115_top; hierarchy -check -top de2_115_top; proc; check -assert" >/dev/null 2>&1; then echo "OK   yosys gap=$1 idle_chk=$2 accepted"; else echo "FAIL yosys gap=$1 idle_chk=$2 should be accepted"; rc=1; fi
done
rm -rf $T; [ $rc -eq 0 ] && echo "ADC_GAP GUARD CHECKS PASSED" || echo "ADC_GAP GUARD CHECKS FAILED"; exit $rc
