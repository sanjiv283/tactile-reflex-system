// Formal properties of safety_governor + pwm_generator, checked from a FREE initial state (all registers arbitrary, inputs free every clock).
// Each property is a one-step relation of the transition function (the state after a clock depends only on the previous state and inputs), so a check with no
// counterexample from every state means the property holds in every state the design can reach, for all input sequences. The harness' own delayed copies
// (p_*) are skipped for the first two steps (init gating). This is a proof for THESE two modules; it says nothing about the other modules, the predictor
// (not asserted), timing, or the physical world. Needs the instrumented copies made by tools/formal_check.py (they only add output ports dbg_*).
module gov_props #(parameter PRED_EN = 0) (
    input clk, input rst_n, input in_valid, input [11:0] force_code, input [7:0] lut_cmd,
    input adc_invalid, input sensor_fault, input estop_active, input ai_valid, input [1:0] ai_class
);
    localparam [11:0] MAX = 12'hA00, REL = 12'h900; localparam [7:0] HOLD = 8'd64, EXCESS = 8'd24;
    wire [7:0] cmd_out; wire safe_state; wire [4:0] trip_reason; wire ai_used, ai_overridden, pwm_out, armed, fo; wire [11:0] dcnt; wire [7:0] dda;
    safety_governor #(.PRED_EN(PRED_EN), .PRED_WIN(3)) g (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .force_code(force_code), .lut_cmd(lut_cmd),
        .adc_invalid(adc_invalid), .sensor_fault(sensor_fault), .estop_active(estop_active), .ai_valid(ai_valid), .ai_class(ai_class),
        .cmd_out(cmd_out), .safe_state(safe_state), .trip_reason(trip_reason), .ai_used(ai_used), .ai_overridden(ai_overridden), .dbg_armed(armed), .dbg_force_over(fo));
    pwm_generator p (.clk(clk), .rst_n(rst_n), .duty(cmd_out), .kill(safe_state), .pwm_out(pwm_out), .dbg_cnt(dcnt), .dbg_da(dda));
    reg [1:0] init = 0; reg p_rst_n = 1, p_sf = 0, p_es = 0, p_inv = 0, p_aiv = 0, p_valid = 0, p_a = 0, p_fo = 0, p_safe = 0; reg [1:0] p_cls = 0; reg [7:0] p_lut = 0; reg [11:0] p_force = 0;
    always @(posedge clk) begin
        init <= {init[0], 1'b1}; p_rst_n <= rst_n; p_sf <= sensor_fault; p_es <= estop_active; p_inv <= adc_invalid; p_aiv <= ai_valid; p_cls <= ai_class;
        p_valid <= in_valid; p_force <= force_code; p_lut <= lut_cmd; p_a <= armed; p_fo <= fo; p_safe <= safe_state;
    end
    wire cause = p_sf | p_es | p_inv;
    always @* if (init[1]) begin
        assert (!safe_state || cmd_out == 8'd0);                                   // P1  a safe state carries no command
        assert (!p_safe || !pwm_out);                                              // P2  PWM output low one clock after a safe state (through the real PWM stage)
        assert (!p_rst_n || !cause || (safe_state && cmd_out == 8'd0));            // P3  e-stop / sensor fault / invalid ADC force the safe state on the next clock
        assert (!p_rst_n || !(p_valid && p_force >= MAX) || safe_state);           // P4  a valid force >= FORCE_MAX forces the safe state, whatever the AI says
        assert (safe_state || cmd_out <= p_lut);                                   // P5  command never above the LUT command (the AI can only lower it)
        assert (p_rst_n || safe_state);                                            // P6  reset forces the safe state
        assert (ai_overridden == (p_rst_n && safe_state && p_aiv && p_cls != 2'd3)); // P7  override flag is exactly: safe state while a valid AI class other than 3 was present
        assert (ai_used == (p_rst_n && p_aiv && !safe_state));                     // P8  the AI counts as used only while not in the safe state
        assert (!(p_rst_n && !safe_state && p_aiv && p_cls == 2'd2) || cmd_out <= HOLD);   // P9  AI class 2 caps the command at HOLD_CAP (64)
        assert (!(p_rst_n && !safe_state && p_aiv && p_cls == 2'd3) || cmd_out <= EXCESS); // P10 AI class 3 caps the command at EXCESS_CAP (24)
        assert (p_a || safe_state);                                                // P11 not armed (no valid sample seen since reset) forces the safe state
        assert (armed == (p_rst_n && (p_a || p_valid)));                           // P12 armed is set by the first valid sample and cleared only by reset
        assert (fo == (p_rst_n && (p_valid ? (p_force >= MAX ? 1'b1 : (p_force < REL ? 1'b0 : p_fo)) : p_fo))); // P13 force latch: set at MAX, cleared only below REL (hysteresis), held between
        assert (!fo || safe_state);                                                // P14 the force latch forces the safe state
        if (PRED_EN == 0)
            assert (safe_state == (!p_rst_n || fo || cause || !p_a));              // P15 (predictor off) the safe state is asserted for exactly the documented causes, nothing else
    end
endmodule
