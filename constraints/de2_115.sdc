create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty
# Asynchronous inputs are synchronised in RTL (two flip-flops)
set_false_path -from [get_ports {KEY[*] UART_RXD ESTOP_EXT_N ADC_MISO}]
