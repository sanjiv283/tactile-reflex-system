`timescale 1ns / 1ps
// NEGATIVE / BOUNDARY TEST for rtl/safety_governor.v - selected with -D<CASE> by run_sim.sh.
// Each BAD_* case changes ONE parameter and MUST FAIL to elaborate through its own guard.
// OK_* cases are accepted boundary configurations and MUST elaborate.
module tb_governor_bad_param;
`ifdef BAD_CLK_LOW
    localparam CLK = 500_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_CLK_FRAC
    localparam CLK = 1_500_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_TIMEOUT
    localparam CLK = 1_000_000, TO = 0, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_LIMITS_ORDER
    localparam CLK = 1_000_000, TO = 1000, PMIN = 2000, PMAX = 1000, SAFE = 1500, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_LIMITS_WIDTH
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 4096, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_PMIN_NEG
    localparam CLK = 1_000_000, TO = 1000, PMIN = -1, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_FRES_NEG
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = -1, FHI = 1015;
`elsif BAD_SAFE_LOW
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 500, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_SAFE_HIGH
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 2001, FMAX = 900, FRES = 800, FHI = 1015;
`elsif BAD_FMAX_HIGH
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 1024, FRES = 800, FHI = 1015;
`elsif BAD_FMAX_ZERO
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 0, FRES = 0, FHI = 1015;
`elsif BAD_FRES
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 901, FHI = 1015;
`elsif BAD_FHI_HIGH
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 1024;
`elsif BAD_FHI_ZERO
    localparam CLK = 1_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 0;
`elsif OK_LOW
    // smallest clock/timeout, equal limits and SAFE, no hysteresis band, thresholds at the bottom
    localparam CLK = 1_000_000, TO = 1, PMIN = 1500, PMAX = 1500, SAFE = 1500, FMAX = 1, FRES = 1, FHI = 1;
`elsif OK_HIGH
    // top of every range; RESUME = 0 (over-force never clears); FAULT_HI below FORCE_MAX is allowed
    localparam CLK = 100_000_000, TO = 1000, PMIN = 0, PMAX = 4095, SAFE = 4095, FMAX = 1023, FRES = 0, FHI = 1023;
`elsif OK_FHI_BELOW_FMAX
    localparam CLK = 50_000_000, TO = 1000, PMIN = 1000, PMAX = 2000, SAFE = 1000, FMAX = 900, FRES = 800, FHI = 850;
`else
    UNDEFINED_CASE_SELECTOR u_must_fail ();
`endif
    wire [11:0] p; wire t; wire [3:0] f;
    safety_governor #(.CLK_HZ(CLK), .ADC_TIMEOUT_US(TO), .PULSE_MIN_US(PMIN), .PULSE_MAX_US(PMAX),
                      .SAFE_PULSE_US(SAFE), .FORCE_MAX(FMAX), .FORCE_RESUME(FRES), .ADC_FAULT_HI(FHI)) dut (
        .clk(1'b0), .rst(1'b1), .estop(1'b0), .grip_en(1'b1), .adc_value(10'd0), .adc_valid(1'b0),
        .lut_pulse_us(12'd1500), .lut_valid(1'b0), .pulse_us(p), .cmd_toggle(t), .fault(f));
endmodule
