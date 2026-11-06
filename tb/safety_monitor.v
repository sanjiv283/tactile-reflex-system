`timescale 1ns/1ps
// Cycle-accurate safety invariant monitor (simulation only). Instantiated next to a DUT in the system-level testbenches, so the
// invariants are checked on EVERY clock of EVERY scenario, not only at the points a directed test happens to look at.
// Inputs are sampled before each clock edge; "prev_*" are the values sampled at the previous edge, so a check at edge k+1 tests the
// registered consequence of the inputs seen at edge k.
//   S1  safe_state(k) -> cmd_out(k)==0                      (a safe state never carries a command)
//   S2  safe_state(k) -> pwm_out(k+1)==0                    (the PWM kill takes effect within one clock)
//   S3  estop|sensor_fault|adc_invalid(k) -> safe_state(k+1)  and  cmd_out(k+1)==0
//   S4  lut_valid & force>=FORCE_MAX (k) -> safe_state(k+1)    (hard force limit, whatever the AI says)
//   S5  not safe(k+1) -> cmd_out(k+1) <= lut_cmd(k)         (the AI / limiter can only LOWER the command)
//   S6  reset (k) -> safe_state(k+1) and pwm_out(k+2)==0   (reset forces the safe state)
// viol counts violations, checks counts evaluated invariants (so a monitor that never ran is visible).
module safety_monitor #(parameter [11:0] FORCE_MAX = 12'hA00, parameter NAME = "mon") (
    input wire clk, input wire rst_s,
    input wire safe_state, input wire pwm_out, input wire [7:0] cmd_out, input wire [7:0] lut_cmd,
    input wire lut_valid, input wire [11:0] lut_force,
    input wire estop_active, input wire sensor_fault, input wire adc_invalid
);
    integer viol = 0, checks = 0, started = 0;
    reg p_safe = 1, p_rst_low = 0, p_rst_low2 = 0, p_cause = 0, p_over = 0; reg [7:0] p_lut = 0;
    task bad(input [255:0] m); begin viol = viol + 1; if (viol <= 5) $display("FAIL SAFETY %0s @%0t: %0s", NAME, $time, m); end endtask
    always @(posedge clk) begin
        if (started >= 2) begin
            checks = checks + 6;
            if (safe_state && cmd_out !== 8'd0)                                   bad("S1 safe_state with nonzero cmd");
            if (p_safe && pwm_out !== 1'b0)                                       bad("S2 pwm high after safe_state");
            if (p_cause && !(safe_state === 1'b1 && cmd_out === 8'd0))            bad("S3 fault cause not in safe state");
            if (p_over && safe_state !== 1'b1)                                    bad("S4 force limit not enforced");
            if (!safe_state && cmd_out > p_lut)                                   bad("S5 cmd above LUT command");
            if (p_rst_low && safe_state !== 1'b1)                                 bad("S6 reset did not force safe state");
            if (p_rst_low2 && pwm_out !== 1'b0)                                   bad("S6 pwm high after reset");
        end
        if (^{safe_state, pwm_out, cmd_out} !== 1'bx) started = started + 1; else started = 0;
        p_safe <= safe_state; p_rst_low2 <= p_rst_low; p_rst_low <= !rst_s;
        p_cause <= (estop_active | sensor_fault | adc_invalid) & rst_s;
        p_over <= lut_valid & (lut_force >= FORCE_MAX) & rst_s; p_lut <= lut_cmd;
    end
endmodule
