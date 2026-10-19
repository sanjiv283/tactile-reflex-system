# Timing constraints for the DE2-115 wrapper (TactileReflexive). Not yet run through Quartus: review the timing report.
# 50 MHz board clock = 20 ns period.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# Human inputs (push-buttons KEY, slide switches SW): asynchronous to CLOCK_50. Each one passes through a 2-flop
# synchroniser in the RTL (rtl/reflex_top.v), so no timing relationship to the clock is claimed.
set_false_path -from [get_ports {KEY[*] SW[*]}]

# MISO (GPIO[3]): launched by the external MCP3008 up to about 200 ns after an SCLK edge that this FPGA generated, and sampled
# by the RTL at least 25 clocks (500 ns at 50 MHz) later through a 2-flop synchroniser (rtl/adc_spi_interface.v). That is not a
# single-cycle relationship to CLOCK_50, so a normal input delay would report false violations. Exception limited to this one pin.
set_false_path -from [get_ports {GPIO[3]}]

# Deliberately NO exceptions on outputs and no set_input_delay / set_output_delay (no external timing values are known yet).
# The LEDs, the SPI outputs (GPIO[0..2]) and the servo output (GPIO[4]) will appear as unconstrained paths in the timing report.
