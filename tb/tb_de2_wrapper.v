`timescale 1ns / 1ps
// Board-level simulation of quartus/TactileReflexive.v (the DE2-115 wrapper) with the MCP3008 model: normal ADC operation,
// missing / invalid ADC frames, reset, emergency stop, over-force and range faults, grip disable, and a safe servo output.
// 50 MHz clock. The servo frame is FRAME_US_TB (2.5 ms fast run, or the real 20 ms frame in the extended suite). Pins are the wrapper's logical GPIO bits:
//   GPIO[0] CS, GPIO[1] SCLK, GPIO[2] MOSI (outputs)   GPIO[3] MISO (input)   GPIO[4] servo.
// Stimulus is applied right after the falling edge of a servo pulse, so the NEXT pulse (one frame later) shows the effect.
// The checks labelled CHARACTERISATION document what the design does today; they are not requirements.
module tb_de2_wrapper;
    parameter FRAME_US_TB = 2500;                    // run_sim.sh: 2500 (fast, default suite) and 20000 (the real 20 ms frame, extended suite)
    reg CLOCK_50 = 0;
    always #10 CLOCK_50 = ~CLOCK_50;                 // 50 MHz

    reg  [3:0]  KEY = 4'b1110;                       // KEY0 pressed (low) = reset; others released (high)
    reg  [17:0] SW  = 18'b1;                         // SW0 = grip enable
    wire [17:0] LEDR;
    wire [8:0]  LEDG;
    wire [35:0] GPIO;

    // MISO source: 0 = MCP3008 model, 1 = ADC disconnected (the FPGA weak pull-up pulls the line high; modelled with pullup),
    //              2 = line stuck low
    reg [1:0] miso_mode = 0;
    wire dout;
    assign GPIO[3] = (miso_mode == 0) ? dout : (miso_mode == 2) ? 1'b0 : 1'bz;
    pullup (GPIO[3]);

    TactileReflexive #(.FRAME_US(FRAME_US_TB)) dut (.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW), .LEDR(LEDR), .LEDG(LEDG), .GPIO(GPIO));
    mcp3008_model adc (.cs_n(GPIO[0]), .sclk(GPIO[1]), .din(GPIO[2]), .dout(dout));

    wire servo = GPIO[4];
    wire rst_int = dut.u_reflex.rst;                 // internal synchronised reset (simulation-only observation)

    integer errors = 0;
    task check(input cond, input [8*104-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- servo pulse monitor: width of every complete pulse in microseconds
    integer last_w = 0, npulse = 0, bad_w = 0, min_w = 99999, max_w = 0, nframe_err = 0;
    realtime t_rise = 0;
    reg      cut_by_reset = 0;
    always @(posedge servo) begin t_rise = $realtime; cut_by_reset = 0; end
    always @(negedge servo) if (t_rise > 0) begin
        last_w = $rtoi(($realtime - t_rise) / 1000.0 + 0.5);
        if (!cut_by_reset) begin
            npulse = npulse + 1;
            if (last_w < min_w) min_w = last_w;
            if (last_w > max_w) max_w = last_w;
            if (last_w < 1000 || last_w > 2000) bad_w = bad_w + 1;     // every normal pulse must be 1000..2000 us
        end
    end
    always @(posedge LEDR[4]) nframe_err = nframe_err + 1;              // ADC frame-error pulses

    // ---- every-clock monitors (sampled at the falling clock edge, away from the rising-edge updates)
    integer rst_cyc = 0, rst_viol = 0, high_clks = 0, long_high = 0, mon_clks = 0;
    reg     rst_prev = 0;
    always @(negedge CLOCK_50) begin
        mon_clks = mon_clks + 1;
        if (rst_prev) begin rst_cyc = rst_cyc + 1; if (servo !== 1'b0) rst_viol = rst_viol + 1; end   // low on every clock after a reset clock
        if (rst_int) cut_by_reset = 1;
        rst_prev = rst_int;
        if (servo === 1'b1) begin high_clks = high_clks + 1; if (high_clks > 100_000) long_high = long_high + 1; end   // > 2000 us high
        else high_clks = 0;
    end

    task press_reset; begin KEY[0] = 1'b0; #2000; KEY[0] = 1'b1; end endtask
    // Wait for the next servo pulse to end (then 100 ns more). A missing pulse is a FAIL after 3 frames, never a hang.
    integer nfall = 0, tw, n0;
    always @(negedge servo) nfall = nfall + 1;
    task next_pulse;
        begin
            n0 = nfall; tw = 0;
            while (nfall == n0 && tw < 3 * FRAME_US_TB * 50) begin @(posedge CLOCK_50); tw = tw + 1; end
            if (nfall == n0) begin $display("FAIL  no servo pulse within 3 frames"); errors = errors + 1; end
            #100;
        end
    endtask

    initial begin #(FRAME_US_TB * 1000.0 * 120); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end

    initial begin
        #1000;
        // ---------------- reset held (KEY0 pressed), healthy ADC connected
        check(servo === 1'b0 && GPIO[0] === 1'b1 && LEDG[2] === 1'b1, "KEY0 pressed: reset requested, servo low, SPI CS idle high");
        adc.value[0] = 10'd0;
        KEY[0] = 1'b1;
        // ---------------- normal operation, startup
        next_pulse;
        check(last_w == 2000, "startup with healthy ADC: first pulse is the LUT value for code 0 (2000 us)");
        check(LEDR[3:0] === 4'b0000, "no fault after start-up: the ADC timeout does not fire before the first sample");
        adc.value[0] = 10'd640;  next_pulse;
        check(last_w == 1360 && LEDR[3:0] === 4'b0000, "code 640 -> 1360 us (2000 - 16*40), no fault");

        // ---------------- over-force with hysteresis (FORCE_MAX 900, resume below 800)
        adc.value[0] = 10'd920;  next_pulse;
        check(LEDR[0] === 1'b1 && last_w == 1000, "OVER-FORCE (code 920): fault LED 0 on, servo pulse = SAFE 1000 us");
        adc.value[0] = 10'd790;  next_pulse;
        check(LEDR[0] === 1'b0 && last_w == 1216, "force back below 800: over-force clears, LUT value returns (code 790 -> 1216 us)");

        // ---------------- range fault (code >= 1015 = shorted sensor) is latched
        adc.value[0] = 10'd1020; next_pulse;
        check(LEDR[1] === 1'b1 && last_w == 1000, "RANGE FAULT (code 1020): fault LED 1 on, SAFE 1000 us");
        adc.value[0] = 10'd0;    next_pulse;
        check(LEDR[1] === 1'b1 && last_w == 1000, "range fault stays latched after the reading returns to normal (needs reset)");

        // ---------------- reset recovers
        press_reset;
        check(servo === 1'b0 && LEDR[3:0] === 4'b0000, "reset: servo low and all faults cleared");
        next_pulse;
        check(last_w == 2000 && LEDR[3:0] === 4'b0000, "after reset: normal operation again (2000 us for code 0)");

        // ---------------- emergency stop (KEY1 pressed momentarily): latched until reset
        KEY[1] = 1'b0; #2000; KEY[1] = 1'b1;
        next_pulse;
        check(LEDR[3] === 1'b1 && last_w == 1000, "E-STOP (KEY1 tapped): fault LED 3 on, SAFE 1000 us");
        next_pulse;
        check(LEDR[3] === 1'b1 && last_w == 1000, "e-stop button released: still latched, SAFE output (needs reset)");
        press_reset; next_pulse;
        check(LEDR[3] === 1'b0 && last_w == 2000, "reset clears the e-stop latch");

        // ---------------- ADC disconnected: MISO pulled high -> null bit 1 -> invalid frames, no samples
        nframe_err = 0;
        miso_mode = 1; next_pulse; next_pulse;       // two pulses: the 1 ms ADC timeout must expire before the frame is latched (short frame)
        check(nframe_err > 0, "ADC disconnected (MISO pulled high): invalid frames are reported (frame-error LED pulses)");
        check(LEDR[2] === 1'b1 && last_w == 1000, "ADC TIMEOUT latched (fault LED 2) and servo pulse = SAFE 1000 us");
        miso_mode = 0; next_pulse;
        check(LEDR[2] === 1'b1 && last_w == 1000, "ADC reconnected: timeout stays latched until reset");
        press_reset; next_pulse;
        check(LEDR[2] === 1'b0 && last_w == 2000, "reset recovers from the ADC timeout once the ADC is back");

        // ---------------- grip enable switch (not a fault)
        SW[0] = 1'b0; next_pulse;
        check(last_w == 1000 && LEDR[3:0] === 4'b0000, "SW0 = 0 (grip disabled): SAFE 1000 us, no fault flagged");
        SW[0] = 1'b1; next_pulse;
        check(last_w == 2000, "SW0 = 1 again: LUT value returns");

        // ---------------- CHARACTERISATION: MISO stuck low looks like a valid reading of 0
        miso_mode = 2; next_pulse; next_pulse;
        check(LEDR[3:0] === 4'b0000 && last_w == 2000, "CHARACTERISATION: MISO stuck low = valid code 0, no fault, pulse 2000 us (the maximum command)");
        miso_mode = 0; next_pulse;

        // ---------------- summary monitors
        check(npulse >= 14, "monitor ran: at least 14 complete servo pulses were observed (not vacuous)");
        check(bad_w == 0 && min_w >= 1000 && max_w <= 2000, "every complete servo pulse was within 1000..2000 us");
        check(long_high == 0, "servo output was never high for more than 2000 us");
        check(rst_viol == 0 && rst_cyc >= 20, "servo output low on every clock after an internal reset clock (>=20 such clocks)");
        check(adc.violations == 0 && adc.diff_requests == 0, "MCP3008 datasheet timing checks (model) passed at 50 MHz; only single-ended requests");
        $display("INFO  pulses=%0d width min=%0d max=%0d us, monitored clocks=%0d, reset clocks=%0d, frame-error pulses=%0d, ADC conversions=%0d",
                 npulse, min_w, max_w, mon_clks, rst_cyc, nframe_err, adc.conversions);
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
