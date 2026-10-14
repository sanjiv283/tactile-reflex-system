// Independent hardware safety layer. Any fault or over-force forces SAFE_PULSE.
//  - over-force: trips at adc >= FORCE_MAX, releases at adc < FORCE_RESUME (hysteresis)
//  - range fault: adc >= ADC_FAULT_HI, latched until reset
//  - timeout: no adc_valid for ADC_TIMEOUT_US, latched until reset; only adc_valid restarts the timer
//  - e-stop: latched until reset
// Output is held at SAFE_PULSE after reset until the first valid sample.
module safety_governor #(
    parameter CLK_HZ         = 100_000_000,
    parameter ADC_TIMEOUT_US = 1000,
    parameter FORCE_MAX      = 900,
    parameter FORCE_RESUME   = 800,
    parameter ADC_FAULT_HI   = 1015,
    parameter PULSE_MIN      = 1000,
    parameter PULSE_MAX      = 2000,
    parameter SAFE_PULSE     = 2000
) (
    input             clk,
    input             rst,
    input      [9:0]  adc_value,
    input             adc_valid,
    input             estop,
    input      [11:0] lut_pulse,
    output reg [11:0] pulse_out,
    output reg        over_force,
    output reg        fault_range,
    output reg        fault_timeout,
    output reg        fault_estop,
    output            safe_state,
    output reg        cmd_toggle     // flips whenever pulse_out changes
);
    localparam integer TLIM = ADC_TIMEOUT_US * (CLK_HZ / 1_000_000);

    reg [31:0] tcnt;
    reg        seen;

    assign safe_state = over_force | fault_range | fault_timeout | fault_estop;

    wire [11:0] clamped = (lut_pulse < PULSE_MIN) ? PULSE_MIN :
                          (lut_pulse > PULSE_MAX) ? PULSE_MAX : lut_pulse;

    wire [11:0] nxt = (safe_state | ~seen) ? SAFE_PULSE : clamped;

    always @(posedge clk) begin
        if (rst) begin
            cmd_toggle <= 0;
            over_force <= 0; fault_range <= 0; fault_timeout <= 0; fault_estop <= 0;
            tcnt <= 0; seen <= 0; pulse_out <= SAFE_PULSE;
        end else begin
            if (estop) fault_estop <= 1;
            if (adc_valid) begin
                seen <= 1;
                tcnt <= 0;
                if (adc_value >= FORCE_MAX)         over_force <= 1;
                else if (adc_value < FORCE_RESUME)  over_force <= 0;
                if (adc_value >= ADC_FAULT_HI)      fault_range <= 1;
            end else begin
                tcnt <= tcnt + 1;
                if (tcnt >= TLIM) fault_timeout <= 1;
            end
            pulse_out <= nxt;
            if (nxt != pulse_out) cmd_toggle <= ~cmd_toggle;
        end
    end
endmodule
