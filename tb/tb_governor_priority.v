`timescale 1ns / 1ps
// Safety-governor priority / simultaneity / timeout-boundary tests, driving rtl/safety_governor.v directly
// with cycle-exact inputs. Parameter-generic: thresholds below are the governor's own parameters, so the same
// bench is run with the defaults and with a non-default configuration (see run_sim.sh).
// Behaviour under test was read from the RTL:
//   trip   = estop | f_estop | f_timeout | f_range | f_over            (estop input acts combinationally)
//   pulse_us <= SAFE when trip | !grip_en, else clamp(lut) on lut_valid  (pulse_us only changes on lut_valid)
//   timeout: since_sample restarts on adc_valid; f_timeout sets on a non-valid cycle with since_sample == limit,
//            so the longest gap between two adc_valid cycles that does NOT time out is limit+1 cycles.
// Clock 1 MHz so ADC_TIMEOUT_US = number of clocks.
module tb_governor_priority;
    parameter FORCE_MAX      = 900;
    parameter FORCE_RESUME   = 800;
    parameter ADC_FAULT_HI   = 1015;
    parameter PULSE_MIN_US   = 1000;
    parameter PULSE_MAX_US   = 2000;
    parameter SAFE_PULSE_US  = 1000;
    parameter ADC_TIMEOUT_US = 1000;
    localparam TC   = ADC_TIMEOUT_US;                 // timeout limit in clocks (1 MHz clock)
    localparam MARK = PULSE_MIN_US + 111;             // distinctive in-range LUT value

    reg clk = 0;
    always #500 clk = ~clk;

    reg        rst = 1, estop = 0, grip_en = 1, adc_valid = 0, lut_valid = 0;
    reg  [9:0] adc_value = 0;
    reg [11:0] lut_pulse_us = 0;
    wire [11:0] pulse_us;
    wire       cmd_toggle;
    wire [3:0] fault;

    safety_governor #(.CLK_HZ(1_000_000), .FORCE_MAX(FORCE_MAX), .FORCE_RESUME(FORCE_RESUME),
                      .ADC_FAULT_HI(ADC_FAULT_HI), .PULSE_MIN_US(PULSE_MIN_US), .PULSE_MAX_US(PULSE_MAX_US),
                      .SAFE_PULSE_US(SAFE_PULSE_US), .ADC_TIMEOUT_US(ADC_TIMEOUT_US)) dut (
        .clk(clk), .rst(rst), .estop(estop), .grip_en(grip_en),
        .adc_value(adc_value), .adc_valid(adc_valid), .lut_pulse_us(lut_pulse_us), .lut_valid(lut_valid),
        .pulse_us(pulse_us), .cmd_toggle(cmd_toggle), .fault(fault));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s  (fault=%b pulse=%0d)", name, fault, pulse_us); errors = errors + 1; end
        end
    endtask

    // ---------- invariant monitors (sampled on the falling edge)
    reg mon_en = 0;
    integer streak = 0, viol_range = 0, viol_safe = 0, mark_seen = 0, mark2_seen = 0, toggles = 0, lutv = 0;
    reg prev_tog = 0;
    always @(negedge clk) if (mon_en) begin
        if (pulse_us < PULSE_MIN_US || pulse_us > PULSE_MAX_US) viol_range = viol_range + 1;
        if (fault !== 4'b0000 || grip_en === 1'b0) streak = streak + 1; else streak = 0;
        if (streak >= 3 && pulse_us !== SAFE_PULSE_US) viol_safe = viol_safe + 1;
        if (pulse_us === MARK) mark_seen = mark_seen + 1;
        if (pulse_us === MARK + 1) mark2_seen = mark2_seen + 1;
        if (cmd_toggle !== prev_tog) toggles = toggles + 1;
        prev_tog = cmd_toggle;
    end
    always @(posedge clk) if (mon_en && lut_valid) lutv = lutv + 1;

    task nclk(input integer n); repeat (n) @(negedge clk); endtask
    // one ADC sample as reflex_top delivers it: adc_valid, then lut_valid with the LUT value one clock later
    task smp(input [9:0] a, input [11:0] lv);
        begin
            @(negedge clk); adc_value = a; adc_valid = 1; lut_valid = 0;
            @(negedge clk); adc_valid = 0; lut_pulse_us = lv; lut_valid = 1;
            @(negedge clk); lut_valid = 0;
            nclk(2);
        end
    endtask
    task vpulse; begin @(negedge clk); adc_value = 10'd100; adc_valid = 1; @(negedge clk); adc_valid = 0; end endtask
    task do_reset; begin @(negedge clk); rst = 1; nclk(3); rst = 0; nclk(2); end endtask

    integer i;
    reg [11:0] expv;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_governor_priority);
        $display("INFO  governor under test: FORCE_MAX=%0d FORCE_RESUME=%0d ADC_FAULT_HI=%0d pulse %0d..%0d safe=%0d timeout=%0d clk",
                 FORCE_MAX, FORCE_RESUME, ADC_FAULT_HI, PULSE_MIN_US, PULSE_MAX_US, SAFE_PULSE_US, TC);
        nclk(4); rst = 0; nclk(3);
        mon_en = 1;

        // ---- reset state and a normal sample
        check(pulse_us === SAFE_PULSE_US && fault === 4'b0000, "reset: SAFE command, no fault");
        smp(10'd100, MARK);
        check(pulse_us === MARK && fault === 4'b0000, "normal sample passes the LUT value through");

        // ---- clamp to the hard servo limits (exact edges)
        smp(10'd100, PULSE_MIN_US - 1); check(pulse_us === PULSE_MIN_US, "LUT value PULSE_MIN-1 clamps up to PULSE_MIN");
        smp(10'd100, PULSE_MIN_US);     check(pulse_us === PULSE_MIN_US, "LUT value PULSE_MIN passes");
        smp(10'd100, PULSE_MAX_US);     check(pulse_us === PULSE_MAX_US, "LUT value PULSE_MAX passes");
        smp(10'd100, PULSE_MAX_US + 1); check(pulse_us === PULSE_MAX_US, "LUT value PULSE_MAX+1 clamps down to PULSE_MAX");
        smp(10'd100, 12'd0);            check(pulse_us === PULSE_MIN_US, "LUT value 0 clamps to PULSE_MIN");
        smp(10'd100, 12'd4095);         check(pulse_us === PULSE_MAX_US, "LUT value 4095 clamps to PULSE_MAX");

        // ---- thresholds follow the parameters (over-force trip/hold/release, range fault)
        do_reset;
        smp(FORCE_MAX - 1, MARK);       check(fault[0] === 1'b0 && pulse_us === MARK, "FORCE_MAX-1: no over-force");
        smp(FORCE_MAX, MARK);           check(fault[0] === 1'b1 && pulse_us === SAFE_PULSE_US, "FORCE_MAX: over-force trips, SAFE");
        smp(FORCE_RESUME, MARK);        check(fault[0] === 1'b1 && pulse_us === SAFE_PULSE_US, "FORCE_RESUME: still tripped (needs below)");
        smp(FORCE_RESUME - 1, MARK);    check(fault[0] === 1'b0 && pulse_us === MARK, "FORCE_RESUME-1: released, LUT value resumes");
        do_reset;
        smp(ADC_FAULT_HI - 1, MARK);    check(fault[1] === 1'b0, "ADC_FAULT_HI-1: no range fault");
        smp(ADC_FAULT_HI, MARK);        check(fault[1] === 1'b1 && pulse_us === SAFE_PULSE_US, "ADC_FAULT_HI: range fault, SAFE");
        smp(10'd0, MARK);               check(fault[1] === 1'b1 && fault[0] === 1'b0 && pulse_us === SAFE_PULSE_US, "range fault latched, over-force released");

        // ---- e-stop priority: a single-clock pulse latches; nothing overrides it
        do_reset; smp(10'd100, MARK);
        mark_seen = 0;
        @(negedge clk); estop = 1; @(negedge clk); estop = 0; nclk(3);
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US, "1-clock e-stop pulse latches and forces SAFE");
        mark_seen = 0;                                     // the old value was legitimately on the pin until the latch took effect
        smp(10'd100, MARK); smp(10'd0, MARK);
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US && mark_seen == 0, "samples after e-stop cannot override it");
        // e-stop held through a reset is latched again at once
        @(negedge clk); estop = 1; do_reset;
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US, "e-stop held through reset release: latched again, SAFE");
        @(negedge clk); estop = 0; smp(10'd100, MARK);
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US, "releasing e-stop does not clear the latch");
        do_reset; smp(10'd100, MARK);
        check(fault === 4'b0000 && pulse_us === MARK, "reset with e-stop released clears the latch");

        // ---- e-stop in the same cycle as a sample: the sample's LUT value must never reach the output
        do_reset; mark_seen = 0;
        @(negedge clk); estop = 1; adc_value = 10'd100; adc_valid = 1; lut_valid = 0;
        @(negedge clk); estop = 0; adc_valid = 0; lut_pulse_us = MARK; lut_valid = 1;
        @(negedge clk); lut_valid = 0; nclk(3);
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US && mark_seen == 0, "e-stop coincident with a sample: LUT value never output");

        // ---- e-stop arriving in the SAME clock as lut_valid: only the combinational e-stop term in `trip` can stop the value
        //      (the latch is not set yet), so this is the case that term exists for
        do_reset; mark_seen = 0;
        @(negedge clk); adc_value = 10'd100; adc_valid = 1; lut_valid = 0;
        @(negedge clk); adc_valid = 0; lut_pulse_us = MARK; lut_valid = 1; estop = 1;
        @(negedge clk); lut_valid = 0; estop = 0; nclk(3);
        check(fault[3] === 1'b1 && pulse_us === SAFE_PULSE_US && mark_seen == 0, "e-stop in the lut_valid clock: the LUT value is blocked in that very clock");

        // ---- over-force coincident trip: the tripping sample's own LUT value never reaches the output
        do_reset; smp(10'd100, MARK); mark2_seen = 0;
        smp(FORCE_MAX, MARK + 1);
        check(fault[0] === 1'b1 && pulse_us === SAFE_PULSE_US && mark2_seen == 0, "tripping sample: its own LUT value (MARK+1) never output");

        // ---- all faults at once, then partial release
        do_reset; smp(10'd100, MARK);
        @(negedge clk); estop = 1; adc_value = ADC_FAULT_HI; adc_valid = 1; lut_valid = 0;
        @(negedge clk); estop = 0; adc_valid = 0; lut_pulse_us = MARK; lut_valid = 1;
        @(negedge clk); lut_valid = 0; nclk(2);
        check(fault === 4'b1011 && pulse_us === SAFE_PULSE_US, "e-stop + range + over-force in one sample: 1011, SAFE");
        nclk(TC + 5);
        check(fault === 4'b1111 && pulse_us === SAFE_PULSE_US, "then ADC timeout as well: 1111, SAFE");
        smp(10'd0, MARK);
        check(fault === 4'b1110 && pulse_us === SAFE_PULSE_US, "low sample clears only over-force; e-stop, timeout, range stay latched");
        do_reset;
        check(fault === 4'b0000 && pulse_us === SAFE_PULSE_US, "reset clears every latch; command stays SAFE until the first sample");

        // ---- timeout exact boundary: longest gap between adc_valid cycles that does not time out is TC+1
        do_reset; vpulse; nclk(TC - 1);             // second valid lands TC+1 cycles after the first
        vpulse; nclk(4);
        check(fault[2] === 1'b0, "valid-to-valid gap of limit+1 cycles: no timeout");
        do_reset; vpulse; nclk(TC);                 // second valid lands TC+2 cycles after the first
        vpulse; nclk(4);
        check(fault[2] === 1'b1, "valid-to-valid gap of limit+2 cycles: timeout");
        do_reset; nclk(TC - 3); vpulse; nclk(4);
        check(fault[2] === 1'b0, "first sample shortly before the limit after reset: no timeout (timer runs from reset)");
        do_reset; nclk(TC + 4); vpulse; nclk(4);
        check(fault[2] === 1'b1 && pulse_us === SAFE_PULSE_US, "no sample at all for the limit after reset: timeout");

        // ---- grip enable is not a fault, and does not hide faults
        do_reset; smp(10'd100, MARK);
        @(negedge clk); grip_en = 0; nclk(3);
        check(pulse_us === SAFE_PULSE_US && fault === 4'b0000, "grip_en=0: SAFE without any fault bit");
        smp(10'd100, MARK);
        check(pulse_us === SAFE_PULSE_US, "samples while grip is disabled do not change the command");
        @(negedge clk); grip_en = 1; nclk(2);
        check(pulse_us === SAFE_PULSE_US, "re-enabling grip: command stays SAFE until the next sample");
        smp(10'd100, MARK);
        check(pulse_us === MARK, "next sample after re-enable restores the LUT value");
        @(negedge clk); grip_en = 0; @(negedge clk); estop = 1; @(negedge clk); estop = 0; nclk(2);
        check(fault[3] === 1'b1, "e-stop while grip is disabled is still latched");
        @(negedge clk); grip_en = 1; smp(10'd100, MARK);
        check(pulse_us === SAFE_PULSE_US && fault[3] === 1'b1, "re-enabling grip does not release a latched e-stop");

        // ---- reset coincident with a sample: reset wins, the sample leaves no trace
        do_reset;
        @(negedge clk); rst = 1; adc_value = ADC_FAULT_HI; adc_valid = 1;
        @(negedge clk); adc_valid = 0; nclk(2); rst = 0; nclk(3);
        check(fault === 4'b0000 && pulse_us === SAFE_PULSE_US, "sample in the reset cycle is ignored: no fault latched");

        // ---- cmd_toggle flips exactly once per lut_valid, also while SAFE
        do_reset; toggles = 0; lutv = 0;
        smp(10'd100, MARK); smp(FORCE_MAX, MARK); smp(FORCE_MAX, MARK); smp(10'd100, MARK);
        check(toggles == lutv && lutv == 4, "cmd_toggle flips once per lut_valid (4 samples, including tripped ones)");

        // ---- invariants over the whole run
        check(viol_range == 0, "output always within PULSE_MIN..PULSE_MAX (every clock of the run)");
        check(viol_safe == 0, "output is SAFE whenever a fault or grip-disable has held for 3 clocks (every clock of the run)");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #40_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
