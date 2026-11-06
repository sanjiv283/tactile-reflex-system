`timescale 1ns/1ps
// button_debounce and reset_sync, module level. N = DEBOUNCE_CLKS = 32 (the board uses 1,000,000 = 20 ms).
// Covered: clean press/release, bounce on press and on release, short pulses, long press (no re-trigger), asynchronous transitions at
// odd sub-clock times and sub-clock glitches, reset during debouncing, a key held through reset (must NOT count as a press),
// simultaneous activity on independent instances, active-high polarity, and the reset synchroniser (asynchronous assert,
// synchronous release, pulse shorter than a clock still resets).
module tb_debounce;
    reg clk = 0; always #10 clk = ~clk;                       // 50 MHz; rising edges at 10, 30, 50 ... ns
    localparam N = 32;
    reg rst_n = 0;
    reg btnA = 1, btnB = 1, btnC = 0;                          // A, B: active low (idle 1).  C: active high (idle 0)
    wire pA, pB, pC, pulseA, pulseB, pulseC;
    button_debounce #(.DEBOUNCE_CLKS(N), .ACTIVE_LOW(1)) dA (.clk(clk), .rst_n(rst_n), .btn_raw(btnA), .pressed(pA), .press_pulse(pulseA));
    button_debounce #(.DEBOUNCE_CLKS(N), .ACTIVE_LOW(1)) dB (.clk(clk), .rst_n(rst_n), .btn_raw(btnB), .pressed(pB), .press_pulse(pulseB));
    button_debounce #(.DEBOUNCE_CLKS(N), .ACTIVE_LOW(0)) dC (.clk(clk), .rst_n(rst_n), .btn_raw(btnC), .pressed(pC), .press_pulse(pulseC));

    integer cc = 0; always @(posedge clk) cc <= cc + 1;
    integer riseA = 0, fallA = 0, riseB = 0, riseC = 0, pulsesA = 0, pulsesB = 0, pulsesC = 0, async_changes = 0, xcount = 0, t_rise = 0, t_fall = 0;
    always @(posedge pA) begin riseA = riseA + 1; t_rise = cc; end
    always @(negedge pA) begin fallA = fallA + 1; t_fall = cc; end
    always @(posedge pB) riseB = riseB + 1;
    always @(posedge pC) riseC = riseC + 1;
    always @(posedge clk) begin if (pulseA) pulsesA = pulsesA + 1; if (pulseB) pulsesB = pulsesB + 1; if (pulseC) pulsesC = pulsesC + 1; end
    // outputs must change only on a clock edge, and never be X/Z
    always @(pA or pB or pC or pulseA or pulseB or pulseC) begin
        if (($time % 20) != 10 && rst_n) async_changes = async_changes + 1;
        if ((^{pA, pB, pC, pulseA, pulseB, pulseC}) === 1'bx) xcount = xcount + 1;
    end

    integer pass = 0, fail = 0, vectors = 0;
    task check(input c, input [447:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task clks(input integer n); begin repeat (n) @(posedge clk); end endtask
    integer r0, f0, pu0, t0;

    // ---------- reset synchroniser ----------
    reg arst_n = 1; wire srst_n; reset_sync #(.STAGES(2)) rs (.clk(clk), .arst_n(arst_n), .rst_n(srst_n));
    integer rs_release_clk = 0, rs_assert_t = 0; reg prev_srst = 1;

    initial begin
        // power-up reset
        clks(3); rst_n = 1; clks(4);
        check(pA === 1'b0 && pB === 1'b0 && pC === 1'b0, "after reset: no button pressed");

        // ---- 1. clean press, long hold, clean release ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA; @(negedge clk); btnA = 0; t0 = cc; clks(N + 10);
        check(pA === 1'b1 && riseA == r0 + 1, "clean press: output asserts exactly once");
        check(pulsesA == pu0 + 1, "clean press: exactly one press_pulse");
        check(t_rise - t0 >= N && t_rise - t0 <= N + 4, "clean press: asserts after N stable clocks (N .. N+4 incl. synchroniser)");
        r0 = riseA; pu0 = pulsesA; clks(5000);
        check(riseA == r0 && pulsesA == pu0 && pA === 1'b1, "long press (5000 clocks): no re-trigger, level stays asserted");
        vectors = vectors + 1; f0 = fallA; @(negedge clk); btnA = 1; t0 = cc; clks(N + 10);
        check(pA === 1'b0 && fallA == f0 + 1 && t_fall - t0 >= N && t_fall - t0 <= N + 4, "clean release: de-asserts once after N stable clocks");
        check(pulsesA == pu0, "release produces no press_pulse");

        // ---- 2. bounce on press: only the final stable level counts ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA;
        @(negedge clk); btnA = 0; clks(5); btnA = 1; clks(4); btnA = 0; clks(7); btnA = 1; clks(3); btnA = 0; clks(2); btnA = 1; clks(6); btnA = 0;
        clks(N - 4); check(pA === 1'b0, "bounce on press: output still low before the final stable interval completes");
        clks(20); check(pA === 1'b1 && riseA == r0 + 1 && pulsesA == pu0 + 1, "bounce on press: exactly one rising edge and one pulse");

        // ---- 3. bounce on release ----
        vectors = vectors + 1; f0 = fallA;
        @(negedge clk); btnA = 1; clks(3); btnA = 0; clks(5); btnA = 1; clks(2); btnA = 0; clks(4); btnA = 1;
        clks(N - 4); check(pA === 1'b1, "bounce on release: still pressed until the release is stable");
        clks(20); check(pA === 1'b0 && fallA == f0 + 1, "bounce on release: exactly one falling edge");

        // ---- 4. short pulses are ignored ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA;
        @(negedge clk); btnA = 0; clks(N - 8); btnA = 1; clks(2 * N);
        check(riseA == r0 && pulsesA == pu0 && pA === 1'b0, "pulse shorter than N (N-8 clocks): ignored");
        @(negedge clk); btnA = 0; clks(3); btnA = 1; clks(2 * N);
        check(riseA == r0 && pulsesA == pu0, "3-clock pulse: ignored");
        @(negedge clk); btnA = 0; clks(N + 8); btnA = 1; clks(2 * N);
        check(riseA == r0 + 1 && pulsesA == pu0 + 1, "pulse longer than N (N+8 clocks): accepted");

        // ---- 5. asynchronous transitions at odd sub-clock times, glitches shorter than a clock ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA; f0 = fallA; async_changes = 0;
        #3 btnA = 0; #7 btnA = 1; #5 btnA = 0; #2 btnA = 1; #13 btnA = 0; #4 btnA = 1; #1 btnA = 0; #3 btnA = 1; clks(2 * N);
        check(riseA == r0 && pulsesA == pu0, "sub-clock glitches (2..13 ns): ignored");
        #3 btnA = 0; #11 btnA = 1; #7 btnA = 0; clks(N + 10);
        check(pA === 1'b1 && riseA == r0 + 1, "async press with a sub-clock glitch in front: one edge after N clocks");
        #7 btnA = 1; #9 btnA = 0; #6 btnA = 1; clks(2 * N + 10);
        check(pA === 1'b0, "async release with glitches: released");
        check(async_changes == 0, "outputs only ever change on a clock edge");
        check(xcount == 0, "outputs never X/Z");

        // ---- 6. reset during debouncing ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA;
        @(negedge clk); btnA = 0; clks(N / 2); rst_n = 0; clks(3); check(pA === 1'b0 && pulseA === 1'b0, "reset in the middle of debouncing: output low"); rst_n = 1; t0 = cc;
        clks(N - 6); check(pA === 1'b0, "after reset: debounce restarts from zero (not asserted early)");
        clks(40);
        check(pA === 1'b1, "button still held after reset: output asserts after N clocks");
        check(pulsesA == pu0, "key held THROUGH reset: no press_pulse (it must be released and pressed again)");
        @(negedge clk); btnA = 1; clks(2 * N);
        r0 = riseA; pu0 = pulsesA; @(negedge clk); btnA = 0; clks(2 * N);
        check(pulsesA == pu0 + 1, "release then a fresh press after the held-through-reset case: pulse generated");
        @(negedge clk); btnA = 1; clks(2 * N);

        // ---- 7. simultaneous activity on independent instances ----
        vectors = vectors + 1; r0 = riseA; pu0 = pulsesA; f0 = riseB; t0 = pulsesB;
        fork
            begin @(negedge clk); btnA = 0; clks(3); btnA = 1; clks(2); btnA = 0; clks(2 * N); end
            begin @(negedge clk); clks(7); btnB = 0; clks(4); btnB = 1; clks(5); btnB = 0; clks(2 * N); end
            begin @(negedge clk); clks(11); btnC = 1; clks(2); btnC = 0; clks(3); btnC = 1; clks(2 * N); end
        join
        check(riseA == r0 + 1 && pulsesA == pu0 + 1 && pA === 1'b1, "simultaneous: A one press");
        check(riseB == f0 + 1 && pulsesB == t0 + 1 && pB === 1'b1, "simultaneous: B one press, independent of A");
        check(riseC == 1 && pulsesC == 1 && pC === 1'b1, "simultaneous: C (active-high polarity) one press");
        fork begin @(negedge clk); btnA = 1; end begin @(negedge clk); btnB = 1; end begin @(negedge clk); btnC = 0; end join
        clks(2 * N); check(pA === 1'b0 && pB === 1'b0 && pC === 1'b0, "simultaneous release: all three released");

        // ---- 8. reset synchroniser ----
        vectors = vectors + 1;
        check(srst_n === 1'b1, "reset_sync: released while arst_n is high");
        #3 arst_n = 0; #1;
        check(srst_n === 1'b0, "reset_sync: asserts IMMEDIATELY (asynchronously), not on the next clock");
        #50 arst_n = 1; #1;
        check(srst_n === 1'b0, "reset_sync: stays asserted just after arst_n is released (release is synchronous)");
        clks(1); #1; check(srst_n === 1'b0, "reset_sync: still asserted after one clock (2-stage)");
        clks(1); #1; check(srst_n === 1'b1, "reset_sync: released after two clocks");
        // pulse far shorter than a clock period (3 ns) must still reset
        clks(3); #4 arst_n = 0; #3 arst_n = 1; #1; check(srst_n === 1'b0, "reset_sync: a 3 ns pulse (shorter than the clock) still resets");
        clks(4); check(srst_n === 1'b1, "reset_sync: recovers after the short pulse");

        $display("TB tb_debounce: PASS %0d FAIL %0d VECTORS %0d NOTE button_debounce+reset_sync only; board uses N=1000000", pass, fail, vectors);
        $finish;
    end
    initial begin #50_000_000; $display("TB tb_debounce: TIMEOUT"); $finish; end
endmodule
