#!/bin/sh
# Runs every test; exits 1 on any failure (Icarus itself always exits 0).
# Usage: sh run_sim.sh      (needs iverilog + vvp)
cd "$(dirname "$0")" || exit 1
B=$(mktemp -d); fail=0
CORE="rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v rtl/reflex_top.v"

run() {  # name, vvp-image-args...
    name=$1; shift
    out=$(vvp "$@") ; echo "$out" | grep -E 'INFO|FAIL|VIOLATION|DONE'
    echo "$out" | grep -q '=== DONE: 0 error(s) ===' || { echo "!! $name FAILED"; fail=1; }
}

echo "--- Stage 1 regression";            iverilog -g2012 -o $B/s1 $CORE tb/tb_reflex_top.v || fail=1
run stage1 $B/s1
echo "--- ADC SPI (100 MHz / 1 MHz)";     iverilog -g2012 -o $B/a rtl/adc_spi_interface.v tb/mcp3008_model.v tb/tb_adc_spi_interface.v || fail=1
run adc $B/a
echo "--- ADC SPI worst case (27 MHz / 1.35 MHz)"
iverilog -g2012 -P tb_adc_spi_interface.CLK_HZ=27000000 -P tb_adc_spi_interface.SCLK_HZ=1350000 \
    -o $B/a27 rtl/adc_spi_interface.v tb/mcp3008_model.v tb/tb_adc_spi_interface.v || fail=1
run adc27 $B/a27
echo "--- Integration";                   iverilog -g2012 -o $B/s2 $CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v || fail=1
run integration $B/s2
echo "--- Bad parameter must not compile"
if iverilog -g2012 -o $B/bad rtl/adc_spi_interface.v tb/tb_adc_bad_param.v 2>/dev/null; then
    echo "!! bad-parameter test compiled (it must fail)"; fail=1
else echo "OK: rejected at compile time"; fi

rm -rf "$B"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
