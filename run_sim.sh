#!/bin/sh
# Runs every testbench with Icarus Verilog and prints a per-test summary.
#   sh run_sim.sh              default suite (about 2 minutes)
#   sh run_sim.sh --extended   default suite + 20 ms-frame integration and slower repeats (about 5-6 minutes)
#   EXTENDED=1 sh run_sim.sh   same as --extended
# Exit code is nonzero if anything fails (Icarus itself always exits 0).
# Generated files (sim_*, *.log, *.vcd) are ignored by .gitignore.
cd "$(dirname "$0")" || exit 1
extended=0
[ "$EXTENDED" = "1" ] && extended=1
for a in "$@"; do
    case $a in
        --extended) extended=1 ;;
        *) echo "usage: sh run_sim.sh [--extended]"; exit 2 ;;
    esac
done
fail=0
SUM=sim_summary.log
: > "$SUM"
record() { printf '%-17s %-8s %s\n' "$1" "$2" "$3" >> "$SUM"; }

run() {
    name=$1; shift
    echo "--- $name"
    if ! iverilog -g2005 -o "sim_$name" "$@"; then
        echo "COMPILE FAIL: $name"; fail=1; record "$name" FAIL "compile error"; return
    fi
    # no pipe: in plain sh, "vvp | tee" would report tee's exit status, not vvp's
    vvp -n "sim_$name" > "sim_$name.log"; vrc=$?
    cat "sim_$name.log"
    npass=$(grep -c '^PASS' "sim_$name.log"); nfail=$(grep -c '^FAIL' "sim_$name.log")
    if grep -q "=== DONE: 0 error(s) ===" "sim_$name.log" && [ "$nfail" -eq 0 ] && [ "$npass" -gt 0 ] && [ "$vrc" -eq 0 ]; then
        record "$name" PASS "$npass checks passed"
    else
        echo "TEST FAIL: $name"; fail=1
        record "$name" FAIL "$npass passed, $nfail failed (or vvp exit $vrc / no clean DONE line / watchdog / no PASS lines)"
    fi
}

RTL_CORE="rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v"
ADC="rtl/adc_spi_interface.v tb/mcp3008_model.v tb/tb_adc_spi_interface.v"
SPI="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v"
UART_RTL="rtl/uart_rx.v rtl/uart_tx.v rtl/upload_resp_tx.v rtl/lut_upload_ctrl.v rtl/reflex_top_uart.v"
UART_TOP="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v $UART_RTL tb/mcp3008_model.v tb/tb_reflex_top_uart.v"
HOST_TOP="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v $UART_RTL tb/mcp3008_model.v tb/uart_monitor.v tb/tb_reflex_top_host.v"
SAFE_UP="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v $UART_RTL tb/mcp3008_model.v tb/uart_monitor.v tb/tb_safety_vs_upload.v"
RESP="rtl/uart_tx.v rtl/upload_resp_tx.v tb/uart_monitor.v tb/tb_resp_robust.v"
GOV_CFG="-Ptb_governor_priority.FORCE_MAX=500 -Ptb_governor_priority.FORCE_RESUME=400 -Ptb_governor_priority.ADC_FAULT_HI=600 -Ptb_governor_priority.PULSE_MIN_US=1200 -Ptb_governor_priority.PULSE_MAX_US=1800 -Ptb_governor_priority.SAFE_PULSE_US=1500 -Ptb_governor_priority.ADC_TIMEOUT_US=50"

run reflex   $RTL_CORE tb/tb_reflex_top.v
run boundary $RTL_CORE tb/tb_governor_boundary.v
run adc      $ADC
run adc_27m  -Ptb_adc_spi_interface.CLK_HZ=27000000 -Ptb_adc_spi_interface.SCLK_HZ=1350000 $ADC
run spi_top  $SPI
run uart_rx     rtl/uart_rx.v tb/tb_uart_rx.v
run uart_rx_27m -Ptb_uart_rx.CLK_HZ=27000000 rtl/uart_rx.v tb/tb_uart_rx.v
run uart_rx_1m  -Ptb_uart_rx.BAUD=1000000 rtl/uart_rx.v tb/tb_uart_rx.v
run lut_ctrl    rtl/lut_engine.v rtl/lut_upload_ctrl.v tb/tb_lut_upload_ctrl.v
run uart_top    $UART_TOP
run uart_tx     rtl/uart_tx.v rtl/uart_rx.v tb/uart_monitor.v tb/tb_uart_tx.v
run uart_tx_27m -Ptb_uart_tx.CLK_HZ=27000000 rtl/uart_tx.v rtl/uart_rx.v tb/uart_monitor.v tb/tb_uart_tx.v
run uart_tx_1m  -Ptb_uart_tx.BAUD=1000000 rtl/uart_tx.v rtl/uart_rx.v tb/uart_monitor.v tb/tb_uart_tx.v
run resp_tx     rtl/uart_tx.v rtl/upload_resp_tx.v tb/uart_monitor.v tb/tb_upload_resp_tx.v
run host_top    $HOST_TOP

# ---- Stage 5: robustness and safety verification
run gov_prio      rtl/safety_governor.v tb/tb_governor_priority.v
run gov_prio_cfg  $GOV_CFG rtl/safety_governor.v tb/tb_governor_priority.v
run reflex_sweep  $RTL_CORE tb/tb_reflex_top_sweep.v
run servo_pwm     rtl/servo_pwm_generator.v tb/tb_servo_pwm.v
run lut_engine    rtl/lut_engine.v tb/tb_lut_engine.v
run ctrl_timing   rtl/lut_upload_ctrl.v tb/tb_ctrl_timing.v
run ctrl_timing_2m -Ptb_ctrl_timing.CLK_HZ_P=2000000 -Ptb_ctrl_timing.TIMEOUT_US_P=25 rtl/lut_upload_ctrl.v tb/tb_ctrl_timing.v
run commit_race   rtl/lut_upload_ctrl.v rtl/lut_engine.v rtl/upload_resp_tx.v tb/tb_commit_reset_race.v
run resp_robust   $RESP
run resp_robust_d3 -Ptb_resp_robust.DEPTH_P=3 $RESP
run resp_robust_d8 -Ptb_resp_robust.DEPTH_P=8 $RESP
run safety_up     $SAFE_UP
run fault_latency $RTL_CORE tb/tb_fault_latency.v
# supported configurations not simulated before: 50 MHz, and the tightest allowed clock/baud ratios
run adc_50m       -Ptb_adc_spi_interface.CLK_HZ=50000000 $ADC
run adc_16m       -Ptb_adc_spi_interface.CLK_HZ=16000000 $ADC
run uart_rx_50m   -Ptb_uart_rx.CLK_HZ=50000000 rtl/uart_rx.v tb/tb_uart_rx.v
run uart_rx_min   -Ptb_uart_rx.CLK_HZ=8000000 -Ptb_uart_rx.BAUD=1000000 rtl/uart_rx.v tb/tb_uart_rx.v
run uart_tx_50m   -Ptb_uart_tx.CLK_HZ=50000000 rtl/uart_tx.v rtl/uart_rx.v tb/uart_monitor.v tb/tb_uart_tx.v
run uart_tx_min   -Ptb_uart_tx.CLK_HZ=8000000 -Ptb_uart_tx.BAUD=1000000 rtl/uart_tx.v rtl/uart_rx.v tb/uart_monitor.v tb/tb_uart_tx.v

# ---- DE2-115 board wrapper (quartus/TactileReflexive.v) with the MCP3008 model: normal, ADC missing/invalid, reset, e-stop,
#      over-force, range fault, grip disable, safe servo output. Fast run here (2.5 ms frame), real 20 ms frame in --extended.
DE2_SYNTH="quartus/TactileReflexive.v rtl/reflex_top_spi.v rtl/reflex_top.v rtl/adc_spi_interface.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v"
DE2="$DE2_SYNTH tb/mcp3008_model.v tb/tb_de2_wrapper.v"
run de2_wrapper $DE2

# ---- Stage 6B.2: Python LUT generator, and loading of generated files into rtl/lut_engine.v (INIT_FILE / $readmemh)
# Python is part of the regression: $PYTHON, else python3, else python. A missing interpreter is a FAILURE, not a skip.
# Everything generated goes into one temporary directory that is removed afterwards (also on interrupt).
PY=${PYTHON:-}
if [ -z "$PY" ]; then
    if command -v python3 >/dev/null 2>&1; then PY=python3
    elif command -v python >/dev/null 2>&1; then PY=python; fi
fi
LUT_TMP=
cleanup_lut() { if [ -n "$LUT_TMP" ] && [ -d "$LUT_TMP" ]; then rm -rf "$LUT_TMP"; fi; LUT_TMP=; return 0; }
trap cleanup_lut EXIT
trap 'exit 130' HUP INT TERM
# python -B: never write __pycache__ into the repository.

echo "--- lut_gen_selftest"
if [ -z "$PY" ]; then
    echo "TEST FAIL: no python3/python found"; fail=1; record lut_gen_selftest FAIL "no Python interpreter"
elif py_out=$("$PY" -B python/lut_gen.py --test 2>&1) && printf '%s\n' "$py_out" | grep -q "lut_gen self-test passed"; then
    echo "$py_out"; echo "PASS  python/lut_gen.py --test"
    record lut_gen_selftest PASS "python/lut_gen.py --test"
else
    echo "$py_out"; echo "TEST FAIL: lut_gen_selftest"; fail=1
    record lut_gen_selftest FAIL "python/lut_gen.py --test failed (or did not report success)"
fi

# SDC vs the wrapper's real ports (no Quartus needed): every get_ports pattern must match a port, create_clock on an input,
# and no false path may target outputs.
echo "--- sdc_ports"
if [ -z "$PY" ]; then
    echo "TEST FAIL: no python3/python found"; fail=1; record sdc_ports FAIL "no Python interpreter"
elif sdc_out=$("$PY" -B quartus/check_sdc_ports.py 2>&1); then
    echo "$sdc_out"; echo "PASS  quartus/TactileReflexive.sdc matches the wrapper ports"
    record sdc_ports PASS "SDC patterns match wrapper ports, no output false paths"
else
    echo "$sdc_out"; echo "TEST FAIL: sdc_ports"; fail=1
    record sdc_ports FAIL "SDC does not match the wrapper ports (or has an output false path)"
fi

# lutgen NAME START SLOPE MAX FIRST LAST: the real command-line generator writes NAME.hex (what the RTL loads); the
# expected values NAME.dec come from lut_gen.make_lut() in Python as decimal (a different representation and code path).
# FIRST/LAST are the entries the fixture is meant to have (so a fixture can not silently stop hitting a limit).
lutgen() {
    "$PY" -B python/lut_gen.py --start "$2" --slope "$3" --max "$4" -o "$LUT_TMP/$1.hex" >/dev/null || return 1
    "$PY" -B -c 'import sys
sys.path.insert(0, "python")
import lut_gen
lut = lut_gen.make_lut(float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]))
lut_gen.validate(lut)
assert lut[0] == int(sys.argv[5]) and lut[-1] == int(sys.argv[6]), "fixture does not have the intended end values"
open(sys.argv[4], "w").write("".join("%d\n" % v for v in lut))' "$2" "$3" "$4" "$LUT_TMP/$1.dec" "$5" "$6"
}
# lutload NAME HEXFILE DECFILE NEXP: simulate tb_lut_gen_load against that file (-P string parameters need the quotes)
lutload() {
    run "lutload_$1" "-Ptb_lut_gen_load.FILE=\"$2\"" "-Ptb_lut_gen_load.EXPECT=\"$3\"" "-Ptb_lut_gen_load.NEXP=$4" rtl/lut_engine.v tb/tb_lut_gen_load.v
}
# lutuart NAME HEXFILE DECFILE: the same generated file through the real top level reflex_top_uart (tb_lut_uart_top_load)
UARTLUT="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v $UART_RTL tb/mcp3008_model.v tb/tb_lut_uart_top_load.v"
lutuart() {
    run "lutuart_$1" "-Ptb_lut_uart_top_load.FILE=\"$2\"" "-Ptb_lut_uart_top_load.EXPECT=\"$3\"" $UARTLUT
}
# lutgen_reject NAME MESSAGE ARGS...: the generator must refuse (nonzero exit, MESSAGE from validate(), no file written)
lutgen_reject() {
    name=$1; msg=$2; shift 2
    echo "--- $name"
    if [ -z "$PY" ] || [ -z "$LUT_TMP" ]; then
        echo "TEST FAIL: $name (no Python or temporary directory)"; fail=1; record "$name" FAIL "no Python or no temporary directory"; return
    fi
    if out=$("$PY" -B python/lut_gen.py "$@" -o "$LUT_TMP/$name.hex" 2>&1); then
        echo "TEST FAIL: $name accepted"; fail=1; record "$name" FAIL "invalid table was accepted"
    elif [ -e "$LUT_TMP/$name.hex" ]; then
        echo "TEST FAIL: $name wrote a file"; fail=1; record "$name" FAIL "generator wrote a file for an invalid table"
    elif printf '%s\n' "$out" | grep -q "$msg"; then
        echo "PASS  $name rejected: $msg"; record "$name" PASS "generator refused (nonzero exit, no file)"
    else
        echo "$out"; echo "TEST FAIL: $name failed for a different reason"; fail=1; record "$name" FAIL "generator failed, but not through validate()"
    fi
}

if [ -z "$PY" ] || ! LUT_TMP=$(mktemp -d); then
    echo "TEST FAIL: generated-LUT tests need Python and mktemp"; fail=1
    record lutload_all FAIL "no Python interpreter or no temporary directory"
else
    # default parameters (2000 -> 1000 us, reaches both limits); both limits clamped (1800 .. 1000);
    # shallow slope: 64 distinct values with step 3 and no clamping, so any ordering/offset error shows up
    if lutgen default 2000 16 2000 2000 1000; then lutload default "$LUT_TMP/default.hex" "$LUT_TMP/default.dec" 64
    else echo "TEST FAIL: could not generate fixture default"; fail=1; record lutload_default FAIL "fixture generation failed"; fi
    if lutgen clamped 1900 20 1800 1800 1000; then lutload clamped "$LUT_TMP/clamped.hex" "$LUT_TMP/clamped.dec" 64; lutuart clamped "$LUT_TMP/clamped.hex" "$LUT_TMP/clamped.dec"
    else echo "TEST FAIL: could not generate fixture clamped"; fail=1; record lutload_clamped FAIL "fixture generation failed"; fi
    if lutgen mid 1500 3 2000 1500 1311; then lutload mid "$LUT_TMP/mid.hex" "$LUT_TMP/mid.dec" 64; lutuart mid "$LUT_TMP/mid.hex" "$LUT_TMP/mid.dec"
    else echo "TEST FAIL: could not generate fixture mid"; fail=1; record lutload_mid FAIL "fixture generation failed"; fi
    # Characterisation of what the RTL does with a bad file: it does NOT reject it. $readmemh leaves the words the file
    # does not provide unknown (x); the test checks that state, not the simulator's warning text.
    if [ -f "$LUT_TMP/default.hex" ] && head -n 10 "$LUT_TMP/default.hex" > "$LUT_TMP/short.hex"; then
        lutload short "$LUT_TMP/short.hex" "$LUT_TMP/default.dec" 10
    else echo "TEST FAIL: could not build the short file"; fail=1; record lutload_short FAIL "fixture generation failed"; fi
    if [ -f "$LUT_TMP/default.dec" ]; then lutload missing "$LUT_TMP/does_not_exist.hex" "$LUT_TMP/default.dec" 0
    else echo "TEST FAIL: no expected file for the missing-file test"; fail=1; record lutload_missing FAIL "fixture generation failed"; fi
    # Stage 6B.3: what a bad table can do to the servo command (whole reflex_top). MODE 0: out-of-range words are
    # clamped by the governor (portable guarantee). MODE 1: unprovided entries are x in 4-state simulation only
    # (characterisation; see README); a fault, e-stop or reset replaces the x with SAFE.
    INITSAFE="rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v tb/tb_lut_init_safety.v"
    if { printf '%s\n' 000 fff 3e7 7d1 3e8 7d0; n=0; while [ $n -lt 58 ]; do echo 5dc; n=$((n+1)); done; } > "$LUT_TMP/range.hex" &&
       { n=0; while [ $n -lt 10 ]; do echo 5dc; n=$((n+1)); done; } > "$LUT_TMP/short5dc.hex"; then
        run initsafe_range   "-Ptb_lut_init_safety.FILE=\"$LUT_TMP/range.hex\"" -Ptb_lut_init_safety.MODE=0 $INITSAFE
        run initsafe_short   "-Ptb_lut_init_safety.FILE=\"$LUT_TMP/short5dc.hex\"" -Ptb_lut_init_safety.MODE=1 -Ptb_lut_init_safety.NEXP=10 $INITSAFE
        run initsafe_missing "-Ptb_lut_init_safety.FILE=\"$LUT_TMP/does_not_exist.hex\"" -Ptb_lut_init_safety.MODE=1 -Ptb_lut_init_safety.NEXP=0 $INITSAFE
    else echo "TEST FAIL: could not write the init-safety fixtures"; fail=1; record initsafe_all FAIL "fixture generation failed"; fi
    # The Python side does reject bad tables before any file exists.
    lutgen_reject lutgen_rej_range "entries outside" --start 2100 --slope 0 --max 2100
    lutgen_reject lutgen_rej_slope "must not tighten" --start 1000 --slope -16 --max 2000
fi
cleanup_lut

# Negative tests: must FAIL to compile, and only through the parameter check.
# "expected" is one module name, or NAME+OTHER when an invalid setting necessarily trips a second guard too.
# The compiler output must consist solely of "Unknown module type" errors for those names (plus Icarus's own
# summary lines): any other line (a syntax error, a missing file, a warning, another module) fails the test, and
# the first name must be among the errors. iverilog's exit status is tested directly, not through a pipe.
neg() {  # name, expected module name(s), files and -D options...
    name=$1; want=$2; shift 2
    req=${want%%+*}; allowed=$(echo "$want" | tr '+' '|')
    echo "--- $name"
    if out=$(iverilog -g2005 -o "sim_$name" "$@" 2>&1); then
        echo "TEST FAIL: $name compiled (it must not)"; fail=1
        record "$name" FAIL "invalid parameters were accepted"
        return
    fi
    extra=$(printf '%s\n' "$out" | grep -vE "^[^ ]+:[0-9]+: error: Unknown module type: ($allowed)\$|^[0-9]+ error\(s\) during elaboration\.\$|^\*\*\* These modules were missing:\$|^ +($allowed) referenced [0-9]+ times\.\$|^\*\*\*\$")
    if [ -z "$extra" ] && printf '%s\n' "$out" | grep -qE ": error: Unknown module type: $req\$"; then
        echo "PASS  $name rejected by the parameter check"
        record "$name" PASS "rejected at compile time by the parameter check"
    else
        echo "$out"; echo "TEST FAIL: $name failed to compile for a different reason (or with extra diagnostics)"; fail=1
        record "$name" FAIL "compile failed, but not only through the expected parameter check"
    fi
}
neg bad_param      ADC_SPI_INTERFACE_invalid_CLK_HZ_or_SCLK_HZ rtl/adc_spi_interface.v tb/tb_adc_bad_param.v
neg uart_bad_param UART_RX_invalid_CLK_HZ_or_BAUD              rtl/uart_rx.v tb/tb_uart_bad_param.v
neg uart_tx_bad_param UART_TX_invalid_CLK_HZ_or_BAUD           rtl/uart_tx.v tb/tb_uart_tx_bad_param.v
neg resp_bad_param UPLOAD_RESP_TX_invalid_DEPTH                rtl/upload_resp_tx.v tb/tb_resp_bad_param.v
neg ctrl_bad_param LUT_UPLOAD_CTRL_invalid_parameters          rtl/lut_upload_ctrl.v tb/tb_ctrl_bad_param.v

# Stage 6B.1: parameter guards in safety_governor and servo_pwm_generator (one parameter changed per case).
# pos(): the boundary configuration must elaborate cleanly with -Wall (compile only; no simulation needed).
pos() {  # name, files...
    name=$1; shift
    echo "--- $name"
    if out=$(iverilog -g2005 -Wall -o "sim_$name" "$@" 2>&1) && [ -z "$out" ]; then
        echo "PASS  $name accepted"
        record "$name" PASS "valid boundary configuration elaborates"
    else
        echo "$out"; echo "TEST FAIL: $name rejected or warned"; fail=1
        record "$name" FAIL "valid boundary configuration was rejected"
    fi
}
GOV_BP="rtl/safety_governor.v tb/tb_governor_bad_param.v"
SERVO_BP="rtl/servo_pwm_generator.v tb/tb_servo_bad_param.v"
neg gov_bad_clk_low     SAFETY_GOVERNOR_invalid_CLK_HZ          -DBAD_CLK_LOW $GOV_BP
neg gov_bad_clk_frac    SAFETY_GOVERNOR_invalid_CLK_HZ          -DBAD_CLK_FRAC $GOV_BP
neg gov_bad_timeout     SAFETY_GOVERNOR_invalid_ADC_TIMEOUT_US  -DBAD_TIMEOUT $GOV_BP
# an inverted range necessarily leaves SAFE outside it as well, so both guards fire
neg gov_bad_lim_order   SAFETY_GOVERNOR_invalid_PULSE_LIMITS+SAFETY_GOVERNOR_invalid_SAFE_PULSE_US -DBAD_LIMITS_ORDER $GOV_BP
neg gov_bad_lim_width   SAFETY_GOVERNOR_invalid_PULSE_LIMITS    -DBAD_LIMITS_WIDTH $GOV_BP
neg gov_bad_pmin_neg    SAFETY_GOVERNOR_invalid_PULSE_LIMITS    -DBAD_PMIN_NEG $GOV_BP
neg gov_bad_safe_low    SAFETY_GOVERNOR_invalid_SAFE_PULSE_US   -DBAD_SAFE_LOW $GOV_BP
neg gov_bad_safe_high   SAFETY_GOVERNOR_invalid_SAFE_PULSE_US   -DBAD_SAFE_HIGH $GOV_BP
neg gov_bad_fmax_high   SAFETY_GOVERNOR_invalid_FORCE_MAX       -DBAD_FMAX_HIGH $GOV_BP
neg gov_bad_fmax_zero   SAFETY_GOVERNOR_invalid_FORCE_MAX       -DBAD_FMAX_ZERO $GOV_BP
neg gov_bad_fresume     SAFETY_GOVERNOR_invalid_FORCE_RESUME    -DBAD_FRES $GOV_BP
neg gov_bad_fres_neg    SAFETY_GOVERNOR_invalid_FORCE_RESUME    -DBAD_FRES_NEG $GOV_BP
neg gov_bad_fhi_high    SAFETY_GOVERNOR_invalid_ADC_FAULT_HI    -DBAD_FHI_HIGH $GOV_BP
neg gov_bad_fhi_zero    SAFETY_GOVERNOR_invalid_ADC_FAULT_HI    -DBAD_FHI_ZERO $GOV_BP
neg servo_bad_clk_low   SERVO_PWM_GENERATOR_invalid_CLK_HZ      -DBAD_CLK_LOW $SERVO_BP
neg servo_bad_clk_frac  SERVO_PWM_GENERATOR_invalid_CLK_HZ      -DBAD_CLK_FRAC $SERVO_BP
neg servo_bad_frame     SERVO_PWM_GENERATOR_invalid_FRAME_US    -DBAD_FRAME $SERVO_BP
# the guard is inherited by the top level (reflex_top passes FRAME_US/CLK_HZ straight through)
neg top_bad_frame       SERVO_PWM_GENERATOR_invalid_FRAME_US    -DBAD_TOP_FRAME rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v tb/tb_servo_bad_param.v
pos gov_ok_low          -DOK_LOW $GOV_BP
pos gov_ok_high         -DOK_HIGH $GOV_BP
pos gov_ok_fhi_lt_fmax  -DOK_FHI_BELOW_FMAX $GOV_BP
pos servo_ok_min        -DOK_MIN $SERVO_BP
# valid twin of top_bad_frame: same instantiation and files, FRAME_US = 2001
pos top_ok_frame        -DOK_TOP_FRAME rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v tb/tb_servo_bad_param.v

# Lint: every RTL file must compile with all of iverilog's warnings on and print nothing.
echo "--- lint_rtl"
if lint_out=$(iverilog -g2005 -Wall -o sim_lint rtl/*.v 2>&1) && [ -z "$lint_out" ]; then
    echo "PASS  rtl/*.v compile with -Wall and no warnings"
    record lint_rtl PASS "no warnings with iverilog -Wall"
else
    echo "$lint_out"; echo "TEST FAIL: lint_rtl"; fail=1
    record lint_rtl FAIL "iverilog -Wall reported warnings/errors"
fi

# Same for the DE2-115 wrapper with the six RTL files it needs (the top module is named explicitly).
echo "--- lint_wrapper"
if lintw_out=$(iverilog -g2005 -Wall -s TactileReflexive -o sim_lint_wrapper $DE2_SYNTH 2>&1) && [ -z "$lintw_out" ]; then
    echo "PASS  quartus/TactileReflexive.v + 6 RTL files compile with -Wall and no warnings"
    record lint_wrapper PASS "no warnings with iverilog -Wall"
else
    echo "$lintw_out"; echo "TEST FAIL: lint_wrapper"; fail=1
    record lint_wrapper FAIL "iverilog -Wall reported warnings/errors"
fi

# ---- extended tier (slow repeats at other clocks / depths, and the real 20 ms servo frame in the integration test)
if [ $extended -eq 1 ]; then
    run spi_top_20ms     -Ptb_reflex_top_spi.FRAME_US=20000 -Ptb_reflex_top_spi.WATCHDOG_NS=900000000 $SPI
    run servo_pwm_50m    -Ptb_servo_pwm.CLK_HZ=50000000  -Ptb_servo_pwm.FRAME_US=2500 rtl/servo_pwm_generator.v tb/tb_servo_pwm.v
    run servo_pwm_27m    -Ptb_servo_pwm.CLK_HZ=27000000  -Ptb_servo_pwm.FRAME_US=2500 rtl/servo_pwm_generator.v tb/tb_servo_pwm.v
    run servo_pwm_100m   -Ptb_servo_pwm.CLK_HZ=100000000 -Ptb_servo_pwm.FRAME_US=2500 rtl/servo_pwm_generator.v tb/tb_servo_pwm.v
    run resp_robust_d2   -Ptb_resp_robust.DEPTH_P=2 $RESP
    run resp_robust_d5   -Ptb_resp_robust.DEPTH_P=5 $RESP
    run ctrl_timing_50m  -Ptb_ctrl_timing.CLK_HZ_P=50000000 -Ptb_ctrl_timing.TIMEOUT_US_P=1 rtl/lut_upload_ctrl.v tb/tb_ctrl_timing.v
    run de2_wrapper_20ms -Ptb_de2_wrapper.FRAME_US_TB=20000 $DE2
else
    for t in spi_top_20ms servo_pwm_50m servo_pwm_27m servo_pwm_100m resp_robust_d2 resp_robust_d5 ctrl_timing_50m de2_wrapper_20ms; do
        record "$t" SKIPPED "optional: run 'sh run_sim.sh --extended'"
    done
fi

echo
echo "================ SUMMARY ================"
cat "$SUM"
echo "========================================="
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
