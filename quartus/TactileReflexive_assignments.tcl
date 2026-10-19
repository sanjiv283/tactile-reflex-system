# Adds the sources, top-level entity and constraints to the existing Quartus project "TactileReflexive".
# It does NOT assign pin locations (see README_DE2_115.md) and does not touch the .qpf; it edits the project's .qsf only.
# Run it from Quartus: open the TactileReflexive project, then  Tools > Tcl Scripts... > select this file > Run
# (or:  quartus_sh -t TactileReflexive_assignments.tcl   from the project directory).
load_package project
set here [file dirname [file normalize [info script]]]
set rtl  [file normalize [file join $here .. rtl]]

if {![is_project_open]} { project_open TactileReflexive }

set_global_assignment -name TOP_LEVEL_ENTITY TactileReflexive

# Synthesisable RTL only (no testbenches, no tb/mcp3008_model.v). reflex_top_spi pulls in adc_spi_interface and reflex_top.
foreach f {reflex_top_spi.v reflex_top.v adc_spi_interface.v lut_engine.v safety_governor.v servo_pwm_generator.v} {
    set_global_assignment -name VERILOG_FILE [file join $rtl $f]
}
set_global_assignment -name VERILOG_FILE [file join $here TactileReflexive.v]
set_global_assignment -name SDC_FILE     [file join $here TactileReflexive.sdc]

# The RTL uses $clog2. If Analysis & Synthesis rejects it, set the Verilog HDL input version to SystemVerilog_2005 here:
# set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2005

# MISO idles high through the FPGA's weak pull-up, so a disconnected ADC reads as a frame error (the RTL expects this).
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to {GPIO[3]}

export_assignments
puts "TactileReflexive: sources, top-level entity, SDC and MISO pull-up added. Pin locations still need to be imported."
