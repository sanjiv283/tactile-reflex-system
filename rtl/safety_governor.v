`timescale 1ns / 1ps
// Hard safety limits. These are fixed in logic and can NOT be changed by a
// LUT upload, so an AI-generated table can never exceed them.
// fault = {estop, adc_timeout, adc_range, overforce}
//  - estop, adc_timeout, adc_range : latched until reset
//  - overforce                     : set when adc >= FORCE_MAX; cleared by a later sample with adc < FORCE_RESUME
//                                    (hysteresis band FORCE_RESUME..FORCE_MAX). FORCE_RESUME = 0 is accepted but can
//                                    never be satisfied (adc < 0), so over-force then stays latched until reset.
module safety_governor #(
    parameter CLK_HZ         = 100_000_000,
    parameter PULSE_MIN_US   = 1000,  // hard servo limits (check your gripper)
    parameter PULSE_MAX_US   = 2000,
    parameter SAFE_PULSE_US  = 1000,  // safe state = gripper open
    parameter FORCE_MAX      = 900,   // PLACEHOLDER: set from Week-2 calibration
    parameter FORCE_RESUME   = 800,   // PLACEHOLDER: set from Week-2 calibration
    parameter ADC_FAULT_HI   = 1015,  // PLACEHOLDER: reading this high = shorted sensor
    parameter ADC_TIMEOUT_US = 1000   // no ADC sample for this long = ADC fault
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        estop,        // synchronized, active high
    input  wire        grip_en,      // 0 = hold gripper open (not a fault)
    input  wire [9:0]  adc_value,
    input  wire        adc_valid,
    input  wire [11:0] lut_pulse_us,
    input  wire        lut_valid,
    output reg  [11:0] pulse_us,
    output reg         cmd_toggle,   // flips once per processed sample: latency probe
    output wire [3:0]  fault
);
    localparam TIMEOUT_CLKS = ADC_TIMEOUT_US * (CLK_HZ / 1_000_000);
    localparam TW = $clog2(TIMEOUT_CLKS + 1);

    // Elaboration-time parameter checks: an invalid setting refers to a module that does not exist,
    // so compilation fails with the module name below. ADC codes are 10 bits (0..1023); the output is 12 bits.
    generate
        // TIMEOUT_CLKS uses CLK_HZ / 1_000_000 (integer): below 1 MHz it is 0, otherwise a non-whole MHz truncates.
        if (CLK_HZ < 1_000_000 || CLK_HZ % 1_000_000 != 0) begin : g_bad_clk
            SAFETY_GOVERNOR_invalid_CLK_HZ u_param_check ();
        end
        if (ADC_TIMEOUT_US < 1) begin : g_bad_timeout
            SAFETY_GOVERNOR_invalid_ADC_TIMEOUT_US u_param_check ();
        end
        // The clamp needs MIN <= MAX, and both must fit the 12-bit command.
        if (PULSE_MIN_US < 0 || PULSE_MIN_US > PULSE_MAX_US || PULSE_MAX_US > 4095) begin : g_bad_limits
            SAFETY_GOVERNOR_invalid_PULSE_LIMITS u_param_check ();
        end
        // SAFE_PULSE_US bypasses the clamp, so it must already lie inside the hard limits.
        if (SAFE_PULSE_US < PULSE_MIN_US || SAFE_PULSE_US > PULSE_MAX_US) begin : g_bad_safe
            SAFETY_GOVERNOR_invalid_SAFE_PULSE_US u_param_check ();
        end
        // f_over is set when adc >= FORCE_MAX: above 1023 it never trips, 0 trips on every sample.
        if (FORCE_MAX < 1 || FORCE_MAX > 1023) begin : g_bad_force_max
            SAFETY_GOVERNOR_invalid_FORCE_MAX u_param_check ();
        end
        // f_over is cleared when adc < FORCE_RESUME, but only if adc < FORCE_MAX (set wins): a RESUME above MAX
        // would be silently ignored. RESUME == MAX (no hysteresis) and RESUME == 0 (never clears) are legal.
        if (FORCE_RESUME < 0 || FORCE_RESUME > FORCE_MAX) begin : g_bad_force_resume
            SAFETY_GOVERNOR_invalid_FORCE_RESUME u_param_check ();
        end
        // f_range is set when adc >= ADC_FAULT_HI: above 1023 it never trips, 0 trips on every sample.
        // (FAULT_HI <= FORCE_MAX is allowed: the range fault then simply latches first.)
        if (ADC_FAULT_HI < 1 || ADC_FAULT_HI > 1023) begin : g_bad_fault_hi
            SAFETY_GOVERNOR_invalid_ADC_FAULT_HI u_param_check ();
        end
    endgenerate

    reg f_estop, f_timeout, f_range, f_over;
    reg [TW-1:0] since_sample;
    assign fault = {f_estop, f_timeout, f_range, f_over};

    wire trip = estop | f_estop | f_timeout | f_range | f_over;
    wire [11:0] clamped = (lut_pulse_us < PULSE_MIN_US) ? PULSE_MIN_US :
                          (lut_pulse_us > PULSE_MAX_US) ? PULSE_MAX_US : lut_pulse_us;

    always @(posedge clk) begin
        if (rst) begin
            f_estop <= 0; f_timeout <= 0; f_range <= 0; f_over <= 0;
            since_sample <= 0; pulse_us <= SAFE_PULSE_US; cmd_toggle <= 0;
        end else begin
            if (estop) f_estop <= 1'b1;

            if (adc_valid)                         since_sample <= 0;
            else if (since_sample == TIMEOUT_CLKS) f_timeout <= 1'b1;
            else                                   since_sample <= since_sample + 1'b1;

            if (adc_valid) begin
                if (adc_value >= ADC_FAULT_HI) f_range <= 1'b1;
                if (adc_value >= FORCE_MAX)         f_over <= 1'b1;
                else if (adc_value < FORCE_RESUME)  f_over <= 1'b0;
            end

            if (lut_valid) cmd_toggle <= ~cmd_toggle;

            if (trip || !grip_en) pulse_us <= SAFE_PULSE_US;  // override LUT
            else if (lut_valid)   pulse_us <= clamped;
        end
    end
endmodule
