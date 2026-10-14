`timescale 1ns/1ps
// Stage 1 regression: reflex_top driven directly with adc_value / adc_valid.
module tb_reflex_top;
    localparam real TCLK = 10.0;
    reg clk = 0, rst = 1, estop = 0, adc_valid = 0, feed = 0;
    reg [9:0] adc_value = 0, feed_val = 0;
    wire servo_pwm, dbg_cmd_toggle, safe_state, over_force, f_range, f_to, f_estop;
    wire [11:0] pulse_cmd;

    reflex_top #(.CLK_HZ(100_000_000), .FRAME_US(2500)) dut (
        .clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid), .estop(estop),
        .servo_pwm(servo_pwm), .pulse_cmd(pulse_cmd), .dbg_cmd_toggle(dbg_cmd_toggle),
        .safe_state(safe_state), .over_force(over_force), .fault_range(f_range),
        .fault_timeout(f_to), .fault_estop(f_estop));

    always #(TCLK / 2) clk = ~clk;

    integer errors = 0;
    task chk(input c, input [255:0] msg);
        if (!c) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end
    endtask
    task tick(input integer n); repeat (n) @(negedge clk); endtask

    // background sample feeder: one valid every 10 us while feed=1
    always begin
        @(negedge clk);
        if (feed) begin adc_value = feed_val; adc_valid = 1; @(negedge clk); adc_valid = 0; tick(998); end
    end

    task set(input [9:0] v); begin feed_val = v; tick(2000); end endtask   // let 2 samples through

    real t0, w; real last_valid_t;
    task pulse_us(output real us);
        begin @(posedge servo_pwm); t0 = $realtime; @(negedge servo_pwm); us = ($realtime - t0) / 1000.0; end
    endtask
    task check_pulse(input [9:0] v, input integer exp);
        real a, b;
        begin set(v); pulse_us(a); pulse_us(b);       // first pulse may predate the new command
              chk(b > exp - 0.01 && b < exp + 0.01, "servo pulse width"); 
              chk(pulse_cmd == exp, "pulse_cmd value");
              if (!(b > exp - 0.01 && b < exp + 0.01)) $display("  adc=%0d expected %0d us got %0f us", v, exp, b); end
    endtask
    task do_reset; begin feed = 0; rst = 1; tick(4); rst = 0; end endtask

    integer lat; real tv, tt;
    always @(dbg_cmd_toggle) tt = $realtime;

    initial begin
        // ---- reset values
        tick(10);
        chk(pulse_cmd == 2000 && servo_pwm == 0, "reset: SAFE pulse, PWM low");
        chk(!safe_state && !f_to && !f_range && !f_estop && !over_force, "reset: no faults");
        rst = 0;
        // no sample yet: stay at SAFE, not X
        tick(100); chk(pulse_cmd == 2000, "before first sample: SAFE");

        // ---- latency: adc_valid -> dbg_cmd_toggle
        @(negedge clk); adc_value = 400; adc_valid = 1; tv = $realtime; @(negedge clk); adc_valid = 0;
        tick(6);
        lat = (tt - tv + 0.5 * TCLK) / TCLK;       // tv is a negedge; sampled at following posedge
        chk(pulse_cmd == 1600, "latency test value");
        $display("INFO: adc_valid -> dbg_cmd_toggle = %0d clocks after the sampling edge", lat);
        chk(lat == 2, "latency is 2 clocks (+ half-clock alignment)");   // see below

        // ---- force -> pulse mapping (servo output measured)
        feed = 1;
        check_pulse(0, 2000); check_pulse(320, 1680); check_pulse(640, 1360); check_pulse(880, 1120);

        // ---- over-force with hysteresis (900 trips, 800 releases)
        set(899); chk(!over_force && pulse_cmd == 1101, "899 not over-force");
        set(900); chk(over_force && pulse_cmd == 2000, "900 trips over-force");
        set(850); chk(over_force && pulse_cmd == 2000, "850 stays open (hysteresis)");
        set(800); chk(over_force && pulse_cmd == 2000, "800 still open");
        set(799); chk(!over_force && pulse_cmd == 1201, "799 resumes");
        set(700); chk(pulse_cmd == 1300, "700 normal");

        // ---- range fault (>= 1015), latched
        set(1014); chk(!f_range, "1014 no range fault");
        set(1015); chk(f_range && pulse_cmd == 2000, "1015 range fault -> SAFE");
        set(100);  chk(f_range && pulse_cmd == 2000, "range fault latched");
        do_reset; tick(10); chk(!f_range && !over_force && pulse_cmd == 2000, "reset clears range fault");

        // ---- e-stop, latched
        feed = 1; set(300); chk(pulse_cmd == 1700, "pre e-stop");
        @(negedge clk); estop = 1; tick(2); estop = 0; tick(5);
        chk(f_estop && pulse_cmd == 2000, "e-stop -> SAFE");
        tick(2000); chk(f_estop && pulse_cmd == 2000, "e-stop latched");
        do_reset; tick(10); chk(!f_estop, "reset clears e-stop");

        // ---- timeout: only a valid sample restarts it; latched
        feed = 1; set(300); chk(pulse_cmd == 1700 && !f_to, "healthy before timeout test");
        feed = 0; tick(2);
        last_valid_t = $realtime;                      // feeder idle; last valid was <= 10 us ago
        wait (f_to);
        w = ($realtime - last_valid_t) / 1000.0;
        $display("INFO: timeout tripped %0f us after feeder stopped", w);
        chk(w > 900 && w < 1010, "timeout about 1000 us after last sample");
        tick(5); chk(pulse_cmd == 2000 && safe_state, "timeout -> SAFE");
        feed = 1; feed_val = 100; tick(3000);
        chk(f_to && pulse_cmd == 2000, "timeout latched after samples resume");
        do_reset; feed = 1; feed_val = 100; tick(3000);
        chk(!f_to && pulse_cmd == 1900, "reset recovers from timeout");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #400_000_000; $display("FAIL: global timeout"); $finish; end
endmodule
