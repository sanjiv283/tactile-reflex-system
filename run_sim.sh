#!/bin/sh
# Runs every testbench with Icarus Verilog.
# Exit code is nonzero if anything fails (Icarus itself always exits 0).
cd "$(dirname "$0")" || exit 1
fail=0

run() {
    name=$1; shift
    if ! iverilog -g2005 -o "sim_$name" "$@"; then
        echo "COMPILE FAIL: $name"; fail=1; return
    fi
    vvp -n "sim_$name" | tee "sim_$name.log"
    grep -q "=== DONE: 0 error(s) ===" "sim_$name.log" || { echo "TEST FAIL: $name"; fail=1; }
}

RTL_CORE="rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v"
ADC="rtl/adc_spi_interface.v tb/mcp3008_model.v tb/tb_adc_spi_interface.v"

run reflex   $RTL_CORE tb/tb_reflex_top.v
run adc      $ADC
run adc_27m  -Ptb_adc_spi_interface.CLK_HZ=27000000 -Ptb_adc_spi_interface.SCLK_HZ=1350000 $ADC
run spi_top  $RTL_CORE rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v

if iverilog -g2005 -o sim_bad rtl/adc_spi_interface.v tb/tb_adc_bad_param.v 2>/dev/null; then
    echo "TEST FAIL: invalid SCLK_HZ was accepted"; fail=1
else
    echo "PASS  invalid SCLK_HZ rejected at compile time"
fi

[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
