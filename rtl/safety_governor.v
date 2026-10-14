`timescale 1ns / 1ps
// Hard safety limits. These are fixed in logic and can NOT be changed by a
// LUT upload, so an AI-generated table can never exceed them.
// fault = {estop, adc_timeout, adc_range, overforce}
//  - estop, adc_timeout, adc_range : latched until reset
//  - overforce                     : clears with hysteresis (force < FORCE_RESUME)
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
