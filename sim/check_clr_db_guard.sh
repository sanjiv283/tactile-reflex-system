#!/bin/sh
# CLR_DB guard check: CLR_DB >= 2 must elaborate and run; 0, 1 and negative values must FAIL to elaborate in every tool
# (non-zero exit, error names the rule). Also checks the debounce counter width in Yosys. Temp dir only, no writes into the repo.
cd "$(dirname "$0")/.."
T=$(mktemp -d); rc=0
run() {  # db expect(ok|reject)
  out=$(iverilog -g2005 -Ptb_clr_db_guard.DB=$1 -o $T/g.vvp tb/tb_clr_db_guard.v rtl/fault_handler.v 2>&1); c=$?
  if [ "$2" = ok ]; then
    if [ $c -eq 0 ] && vvp $T/g.vvp | grep -q "PASS 5 FAIL 0"; then echo "OK   CLR_DB=$1 accepted: $(vvp $T/g.vvp | grep INFO)"; else echo "FAIL CLR_DB=$1 should be accepted"; rc=1; fi
  else
    if [ $c -ne 0 ] && echo "$out" | grep -q "ERROR_fault_handler_CLR_DB_must_be_at_least_2"; then echo "OK   CLR_DB=$1 rejected (iverilog elaboration error)"; else echo "FAIL CLR_DB=$1 should be rejected"; rc=1; fi
  fi
}
run 2 ok; run 3 ok; run 4 ok; run 7 ok; run 8 ok; run 50000 ok; run 0 reject; run 1 reject; run -1 reject
for v in 0 1; do   # (Yosys chparam cannot parse a negative value; iverilog covers -1)
  yosys -q -p "read_verilog rtl/*.v; chparam -set CLR_DB $v de2_115_top; hierarchy -check -top de2_115_top" >$T/y.log 2>&1 && { echo "FAIL yosys CLR_DB=$v should be rejected"; rc=1; } || { grep -q ERROR_fault_handler_CLR_DB $T/y.log && echo "OK   yosys CLR_DB=$v rejected" || { echo "FAIL yosys CLR_DB=$v wrong error"; rc=1; }; }
  verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -GCLR_DB=$v rtl/*.v --top-module de2_115_top >$T/v.log 2>&1 && { echo "FAIL verilator CLR_DB=$v should be rejected"; rc=1; } || { grep -q ERROR_fault_handler_CLR_DB $T/v.log && echo "OK   verilator CLR_DB=$v rejected" || { echo "FAIL verilator CLR_DB=$v wrong error"; rc=1; }; }
done
for v in 2 50000; do
  w=$(yosys -p "read_verilog rtl/fault_handler.v; chparam -set CLR_DB $v fault_handler; hierarchy -top fault_handler; proc; dump w:run" 2>&1 | grep -m1 "wire width" | awk '{print $3}')
  yosys -q -p "read_verilog rtl/*.v; chparam -set CLR_DB $v de2_115_top; hierarchy -check -top de2_115_top; proc; check -assert" >/dev/null 2>&1 && echo "OK   yosys de2_115_top CLR_DB=$v accepted, run counter width $w" || { echo "FAIL yosys CLR_DB=$v should be accepted"; rc=1; }
done
rm -rf $T; [ $rc -eq 0 ] && echo "CLR_DB GUARD CHECKS PASSED" || echo "CLR_DB GUARD CHECKS FAILED"; exit $rc
