#!/bin/sh
# Runs every testbench with Icarus Verilog and prints a per-test summary.
#   sh run_sim.sh              default suite (about 30 s)
#   sh run_sim.sh --extended   default suite + 100 MHz / 20 ms-servo-frame integration (about 3 min)
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
record() { printf '%-14s %-8s %s\n' "$1" "$2" "$3" >> "$SUM"; }

run() {
    name=$1; shift
    echo "--- $name"
    if ! iverilog -g2005 -o "sim_$name" "$@"; then
        echo "COMPILE FAIL: $name"; fail=1; record "$name" FAIL "compile error"; return
    fi
    vvp -n "sim_$name" | tee "sim_$name.log"
    npass=$(grep -c '^PASS' "sim_$name.log"); nfail=$(grep -c '^FAIL' "sim_$name.log")
    if grep -q "=== DONE: 0 error(s) ===" "sim_$name.log" && [ "$nfail" -eq 0 ]; then
        record "$name" PASS "$npass checks passed"
    else
        echo "TEST FAIL: $name"; fail=1
        record "$name" FAIL "$npass passed, $nfail failed (or no clean DONE line / watchdog)"
    fi
}

RTL_CORE="rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v"
ADC="rtl/adc_spi_interface.v tb/mcp3008_model.v tb/tb_adc_spi_interface.v"
SPI="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v"
UART_TOP="$RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v rtl/uart_rx.v rtl/lut_upload_ctrl.v rtl/reflex_top_uart.v tb/mcp3008_model.v tb/tb_reflex_top_uart.v"

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

if [ $extended -eq 1 ]; then
    run spi_top_20ms -Ptb_reflex_top_spi.FRAME_US=20000 -Ptb_reflex_top_spi.WATCHDOG_NS=900000000 $SPI
else
    record spi_top_20ms SKIPPED "optional: run 'sh run_sim.sh --extended'"
fi

echo
echo "================ SUMMARY ================"
cat "$SUM"
echo "========================================="
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
