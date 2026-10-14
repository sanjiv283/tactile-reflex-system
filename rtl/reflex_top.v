// Stage 1 core: ADC value + 1-clock valid pulse -> LUT -> safety governor -> servo PWM.
// Latency adc_valid -> pulse_cmd / dbg_cmd_toggle: 2 clocks.
module reflex_top #(
    parameter CLK_HZ   = 100_000_000,
    parameter FRAME_US = 20000
) (
    input         clk,
    input         rst,            // synchronous, active high
    input  [9:0]  adc_value,
    input         adc_valid,
    input         estop,
    output        servo_pwm,
    output [11:0] pulse_cmd,
    output        dbg_cmd_toggle,
    output        safe_state,
    output        over_force,
    output        fault_range,
    output        fault_timeout,
    output        fault_estop
);
    // governor PULSE_MAX (2000) must fit inside the servo frame
    generate if (FRAME_US <= 2000) begin : bad_param
        reflex_top_FRAME_US_must_exceed_PULSE_MAX u_err();
    end endgenerate

    wire [11:0] lut_q;
    lut_engine u_lut (.clk(clk), .en(adc_valid), .addr(adc_value), .q(lut_q));

    safety_governor #(.CLK_HZ(CLK_HZ)) u_gov (
        .clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid), .estop(estop),
        .lut_pulse(lut_q), .pulse_out(pulse_cmd), .over_force(over_force),
        .fault_range(fault_range), .fault_timeout(fault_timeout),
        .fault_estop(fault_estop), .safe_state(safe_state), .cmd_toggle(dbg_cmd_toggle));

    servo_pwm_generator #(.CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US)) u_pwm (
        .clk(clk), .rst(rst), .pulse_us(pulse_cmd), .pwm(servo_pwm));

endmodule
