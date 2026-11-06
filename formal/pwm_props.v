// Formal properties of pwm_generator, checked from a FREE initial state (counter, active duty and output arbitrary).
// W1..W6 are one-step relations of the transition function, so a counterexample-free check from every state means they hold in every state the design can
// ever be in, including every point of the 4,096-clock period: the counter value is arbitrary, so the period boundary (counter = 0xFFF) is covered, not just
// the first 14 clocks after reset (which is why an earlier reset-anchored 14-clock check was vacuous for the kill). Needs the instrumented copy made by
// tools/formal_check.py (it only adds the output ports dbg_cnt and dbg_da).
module pwm_props (input clk, input rst_n, input [7:0] duty, input kill);
    wire pwm_out; wire [11:0] cnt; wire [7:0] da;
    pwm_generator p (.clk(clk), .rst_n(rst_n), .duty(duty), .kill(kill), .pwm_out(pwm_out), .dbg_cnt(cnt), .dbg_da(da));
    reg [1:0] init = 0; reg p_kill = 0, p_rst_n = 1; reg [11:0] p_cnt = 0; reg [7:0] p_da = 0, p_duty = 0;
    always @(posedge clk) begin init <= {init[0], 1'b1}; p_kill <= kill; p_rst_n <= rst_n; p_cnt <= cnt; p_da <= da; p_duty <= duty; end
    always @* if (init[1]) begin
        assert (!p_kill || !pwm_out);                                         // W1 kill forces the output low on the next clock (any counter value, any duty)
        assert (p_rst_n || (!pwm_out && da == 8'd0 && cnt == 12'd0));         // W2 reset clears output, active duty and counter
        assert (!p_rst_n || cnt == p_cnt + 12'd1);                             // W3 counter free-runs by +1 per clock: period exactly 4096 clocks
        assert (!p_rst_n || da == ((p_cnt == 12'hFFF) ? p_duty : p_da));      // W4 the active duty changes ONLY at the period boundary, and then to the commanded duty
        assert (!p_rst_n || p_kill || (pwm_out == (p_cnt[11:4] < p_da)));      // W5 when not killed the output is exactly compare(counter[11:4], active duty)
        assert (p_da != 8'd0 || !pwm_out);                                     // W6 an active duty of 0 can never produce a high output
    end
endmodule
