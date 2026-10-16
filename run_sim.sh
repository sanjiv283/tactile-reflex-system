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

# Negative tests: must FAIL to compile, and only through the parameter check.
neg() {  # name, expected module name in the error, files...
    name=$1; want=$2; shift 2
    echo "--- $name"
    if out=$(iverilog -g2005 -o "sim_$name" "$@" 2>&1); then
        echo "TEST FAIL: $name compiled (it must not)"; fail=1
        record "$name" FAIL "invalid parameters were accepted"
    elif echo "$out" | grep -q "$want"; then
        echo "PASS  $name rejected by the parameter check"
        record "$name" PASS "rejected at compile time by the parameter check"
    else
        echo "$out"; echo "TEST FAIL: $name failed to compile for a different reason"; fail=1
        record "$name" FAIL "compile failed, but not through the parameter check"
    fi
}
neg bad_param      ADC_SPI_INTERFACE_invalid_CLK_HZ_or_SCLK_HZ rtl/adc_spi_interface.v tb/tb_adc_bad_param.v
neg uart_bad_param UART_RX_invalid_CLK_HZ_or_BAUD              rtl/uart_rx.v tb/tb_uart_bad_param.v
neg uart_tx_bad_param UART_TX_invalid_CLK_HZ_or_BAUD           rtl/uart_tx.v tb/tb_uart_tx_bad_param.v
neg resp_bad_param UPLOAD_RESP_TX_invalid_DEPTH                rtl/upload_resp_tx.v tb/tb_resp_bad_param.v
neg ctrl_bad_param LUT_UPLOAD_CTRL_invalid_parameters          rtl/lut_upload_ctrl.v tb/tb_ctrl_bad_param.v

# Lint: every RTL file must compile with all of iverilog's warnings on and print nothing.
echo "--- lint_rtl"
if lint_out=$(iverilog -g2005 -Wall -o sim_lint rtl/*.v 2>&1) && [ -z "$lint_out" ]; then
    echo "PASS  rtl/*.v compile with -Wall and no warnings"
    record lint_rtl PASS "no warnings with iverilog -Wall"
else
    echo "$lint_out"; echo "TEST FAIL: lint_rtl"; fail=1
    record lint_rtl FAIL "iverilog -Wall reported warnings/errors"
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
else
    for t in spi_top_20ms servo_pwm_50m servo_pwm_27m servo_pwm_100m resp_robust_d2 resp_robust_d5 ctrl_timing_50m; do
        record "$t" SKIPPED "optional: run 'sh run_sim.sh --extended'"
    done
fi

echo
echo "================ SUMMARY ================"
cat "$SUM"
echo "========================================="
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
