`timescale 1ns/1ps
// System-level reset, clear-key and e-stop behaviour of the DE2-115 wrapper (reset_sync + button_debounce + core).
// Defined behaviour that is asserted here:
//   * ANY reset (even a pulse shorter than a clock) puts the system in the safe state with PWM low, and leaves the e-stop latch set:
//     after every reset an operator must make a deliberate fresh press of the clear key.
//   * The clear key is debounced, acts once per press, and a key that is held (or stuck) can never clear anything.
//   * The e-stop path is NOT delayed by the debouncer: PWM is low within 7 clocks of the key press.
// DEBOUNCE_CLKS = 32 here (board: 1,000,000), so the debounce delay is far larger than the e-stop latency and any debouncing of the stop would be caught.
module tb_reset_recovery;
    reg clk = 0; always #10 clk = ~clk;
    localparam CPB = 16, DB = 32;
    reg [3:0] key = 4'b1111; reg uart_rxd = 1; reg estop_ext_n = 1; reg [11:0] value = 12'h400; reg corrupt = 0;
    wire [17:0] ledr; wire [8:0] ledg; wire uart_txd, cs_n, sclk, miso, pwm, dsv, dsafe;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    de2_115_top #(.CLKS_PER_BIT(CPB), .TX_PERIOD(3000), .AI_TIMEOUT(20000), .PRED_EN(0), .DEBOUNCE_CLKS(DB)) dut (.CLOCK_50(clk), .KEY(key), .LEDR(ledr), .LEDG(ledg),
        .UART_RXD(uart_rxd), .UART_TXD(uart_txd), .ADC_CS_N(cs_n), .ADC_SCLK(sclk), .ADC_MISO(miso), .ESTOP_EXT_N(estop_ext_n),
        .PWM_OUT(pwm), .DBG_SAMPLE_VALID(dsv), .DBG_SAFE_STATE(dsafe));
    wire safe = ledr[0], sfault = ledr[1], estop = ledr[2];

    safety_monitor #(.NAME("reset_recovery")) smon (.clk(clk), .rst_s(dut.u_core.rst_s), .safe_state(dut.u_core.safe_state), .pwm_out(dut.u_core.pwm_out), .cmd_out(dut.u_core.cmd_out), .lut_cmd(dut.u_core.lut_cmd),
        .lut_valid(dut.u_core.lut_valid), .lut_force(dut.u_core.lut_force), .estop_active(dut.u_core.estop_active), .sensor_fault(dut.u_core.sensor_fault), .adc_invalid(dut.u_core.adc_invalid));
    integer pass = 0, fail = 0, vectors = 0, safe_falls = 0, safe_rises = 0, cc = 0, i;
    always @(posedge clk) cc <= cc + 1;
    always @(negedge ledr[0]) safe_falls = safe_falls + 1;
    always @(posedge ledr[0]) safe_rises = safe_rises + 1;
    task check(input c, input [511:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task clks(input integer n); begin repeat (n) @(posedge clk); end endtask
    task frames(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) begin @(posedge clk); while (!dsv) @(posedge clk); end end endtask
    task settle; begin frames(5); clks(DB + 20); end endtask
    task press_clear; begin @(negedge clk); key[1] = 0; clks(DB + 12); key[1] = 1; clks(DB + 12); end endtask      // one deliberate press
    task tx_byte(input [7:0] b); integer k; begin uart_rxd = 0; repeat (CPB) @(posedge clk); for (k = 0; k < 8; k = k + 1) begin uart_rxd = b[k]; repeat (CPB) @(posedge clk); end uart_rxd = 1; repeat (CPB) @(posedge clk); end endtask
    task power_up_and_clear; begin key[3] = 0; clks(6); key[3] = 1; frames(4); press_clear; settle; end endtask

    integer t_fall, lat;
    initial begin
        // ---------- power-up ----------
        key[3] = 0; clks(6); #1; check(pwm === 1'b0 && safe === 1'b1, "power-up reset: PWM low, safe state");
        key[3] = 1; frames(5); clks(DB + 20);
        check(safe === 1'b1 && estop === 1'b1, "after reset release: safe, e-stop latch set (operator clear required)");
        press_clear; settle; check(safe === 1'b0 && estop === 1'b0, "deliberate clear press after power-up: normal operation");

        // ---------- reset during normal operation: asynchronous assert ----------
        vectors = vectors + 1; @(posedge pwm); clks(5); @(negedge clk); #3 key[3] = 0; t_fall = $time; #38;
        check(pwm === 1'b0, "reset pressed at an arbitrary instant: PWM low within 41 ns");
        clks(2); check(safe === 1'b1, "reset: safe state asserted");
        key[3] = 1; frames(5); clks(DB + 20);
        check(safe === 1'b1 && estop === 1'b1 && pwm === 1'b0, "after reset during operation: still safe, latch set, PWM low");
        press_clear; settle; check(safe === 1'b0, "operator clear after the reset: normal operation again");

        // ---------- reset pulse shorter than one clock period ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); #4 key[3] = 0; #3 key[3] = 1;          // 3 ns low, between two clock edges
        clks(8); check(safe === 1'b1 && estop === 1'b1, "3 ns reset pulse (shorter than a clock) still resets the system");
        frames(4); press_clear; settle; check(safe === 1'b0, "recovery after the 3 ns reset pulse");

        // ---------- the same 3 ns pulse must also reach the UART/AI bridge, and the release is synchronous ----------
        vectors = vectors + 1; tx_byte(8'hA5); tx_byte(8'h16); @(negedge clk); #4 key[3] = 0; #3 key[3] = 1; clks(6); tx_byte(8'hE9);
        check(dut.u_bridge.ai_gpio === 16'h0000, "3 ns reset pulse clears a half-received AI packet (the complement byte alone must not complete it)");
        frames(4); press_clear; settle; check(safe === 1'b0, "recovered after the AI-bridge reset scenario");
        vectors = vectors + 1; @(negedge clk); key[3] = 0; clks(3); @(negedge clk); key[3] = 1; #1; check(dut.rst_n === 1'b0, "KEY3 released: wrapper reset still asserted at once");
        @(posedge clk); #1 check(dut.rst_n === 1'b0, "wrapper reset still asserted one clock after KEY3 release (two-stage synchroniser)");
        @(posedge clk); #1 check(dut.rst_n === 1'b1, "wrapper reset released two clocks after KEY3 release");
        frames(4); press_clear; settle; check(safe === 1'b0, "recovered after the reset-release timing scenario");
        // ---------- wrapper-level reset reaches the debouncer even when it is shorter than a clock ----------
        vectors = vectors + 1; @(negedge clk); key[1] = 0; clks(DB + 12);
        check(dut.clear_db === 1'b1, "clear key held: debouncer reports pressed");
        @(negedge clk); #4 key[3] = 0; #3 key[3] = 1; clks(3);
        check(dut.clear_db === 1'b0, "3 ns reset pulse also resets the key debouncer (wrapper reset is synchronised, not raw)");
        key[1] = 1; clks(DB + 12); frames(4); press_clear; settle; check(safe === 1'b0, "recovered after the held-key reset");

        // ---------- e-stop response is not delayed by the debouncer ----------
        vectors = vectors + 1; @(posedge pwm); clks(6); @(negedge clk); key[0] = 0; lat = 0;
        while (pwm !== 1'b0 && lat < 100) begin @(posedge clk); lat = lat + 1; end
        check(lat <= 7, "KEY0 e-stop: PWM low within 7 clocks (the stop path is not debounced)");
        check(safe === 1'b1 && estop === 1'b1, "KEY0 e-stop: safe state and latch");
        @(negedge clk); key[0] = 1; settle; check(safe === 1'b1, "e-stop released: still latched");
        press_clear; settle; check(safe === 1'b0 && estop === 1'b0, "e-stop cleared by a deliberate press");

        // ---------- e-stop bounce: the latch cannot be shaken loose ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); key[0] = 0; clks(2); key[0] = 1; clks(2); key[0] = 0; clks(3); key[0] = 1; clks(1); key[0] = 0; clks(30);
        check(safe === 1'b1 && estop === 1'b1 && pwm === 1'b0, "bouncing e-stop contact: stopped and latched");
        @(negedge clk); key[0] = 1; clks(2); key[0] = 0; clks(2); key[0] = 1; settle; check(safe === 1'b1, "e-stop release with bounce: still latched");
        press_clear; settle; check(safe === 1'b0, "cleared once");

        // ---------- external NC e-stop contact ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); estop_ext_n = 0; lat = 0;
        while (pwm !== 1'b0 && lat < 100) begin @(posedge clk); lat = lat + 1; end
        check(lat <= 7 && safe === 1'b1, "external e-stop contact opens: PWM low within 7 clocks");
        estop_ext_n = 1; settle; check(safe === 1'b1, "external contact closed again: still latched");
        press_clear; settle; check(safe === 1'b0, "external e-stop cleared by a deliberate press");

        // ---------- held / stuck clear key can never defeat the latch ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); key[0] = 0; clks(10); key[1] = 0; clks(DB + 30);      // e-stop pressed, clear pressed AND HELD
        check(safe === 1'b1 && estop === 1'b1, "clear pressed while the e-stop is pressed: ignored");
        key[0] = 1; clks(DB + 60);
        check(safe === 1'b1 && estop === 1'b1, "e-stop released while the clear key is STILL HELD: remains latched (a held key is not a press)");
        key[1] = 1; clks(DB + 30); check(safe === 1'b1, "clear key released: still latched");
        press_clear; settle; check(safe === 1'b0, "release followed by a fresh press: cleared");

        // ---------- clear bounce: exactly one event ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); key[0] = 0; clks(6); key[0] = 1; clks(10); safe_falls = 0;
        @(negedge clk); key[1] = 0; clks(2); key[1] = 1; clks(2); key[1] = 0; clks(3); key[1] = 1; clks(1); key[1] = 0; clks(2); key[1] = 1; clks(2); key[1] = 0;
        clks(DB - 4); check(safe === 1'b1, "bouncing clear key: not released before the press is stable");
        clks(DB + 40); key[1] = 1; settle;
        check(safe === 1'b0 && safe_falls == 1, "bouncing clear key: exactly one release event");

        // ---------- short clear glitch ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); key[0] = 0; clks(6); key[0] = 1; clks(10);
        @(negedge clk); key[1] = 0; clks(DB - 12); key[1] = 1; settle;
        check(safe === 1'b1, "clear glitch shorter than the debounce time: ignored");
        press_clear; settle; check(safe === 1'b0, "full clear press afterwards works");

        // ---------- e-stop and clear pressed at the same instant ----------
        vectors = vectors + 1; @(posedge pwm); @(negedge clk); key[0] = 0; key[1] = 0; clks(DB + 40);
        check(safe === 1'b1 && estop === 1'b1, "e-stop and clear pressed together: the stop wins");
        @(negedge clk); key[0] = 1; key[1] = 1; settle; check(safe === 1'b1, "both released together: still latched");
        press_clear; settle; check(safe === 1'b0, "fresh clear press: recovered");

        // ---------- reset and clear pressed/released together (key held through reset) ----------
        vectors = vectors + 1; @(negedge clk); key[3] = 0; key[1] = 0; clks(6); key[3] = 1; clks(DB + 60);
        check(safe === 1'b1 && estop === 1'b1, "clear key held through a reset: does NOT clear the latch");
        key[1] = 1; clks(DB + 20); check(safe === 1'b1, "clear key released: still latched");
        press_clear; settle; check(safe === 1'b0, "fresh press after the reset: recovered");

        // ---------- reset during a sensor fault ----------
        vectors = vectors + 1; corrupt = 1; frames(12); check(sfault === 1'b1 && safe === 1'b1, "persistent invalid ADC frames: sensor fault latched");
        corrupt = 0; @(negedge clk); key[3] = 0; clks(6); key[3] = 1; frames(6); clks(DB + 20);
        check(sfault === 1'b0 && safe === 1'b1 && estop === 1'b1, "reset clears the sensor fault; e-stop latch still needs a clear press");
        press_clear; settle; check(safe === 1'b0 && sfault === 1'b0, "after reset and clear: normal operation (cause was gone)");
        corrupt = 1; frames(12); check(sfault === 1'b1, "fault again"); @(negedge clk); key[3] = 0; clks(6); key[3] = 1; frames(12); clks(DB + 20);
        check(sfault === 1'b1 && safe === 1'b1, "reset while the cause persists: fault is detected again, system stays safe");
        press_clear; settle; check(safe === 1'b1, "clear press while the cause persists: ignored");
        corrupt = 0; frames(4); press_clear; settle; check(safe === 1'b0 && sfault === 1'b0, "cause removed, deliberate clear: recovered");

        check(smon.viol == 0, "safety_monitor: no invariant violation in any scenario"); $display("TB tb_reset_recovery: PASS %0d FAIL %0d VECTORS %0d NOTE DEBOUNCE_CLKS=32 in simulation; 1000000 on the board", pass, fail, vectors);
        $finish;
    end
    initial begin #150_000_000; $display("TB tb_reset_recovery: TIMEOUT"); $finish; end
endmodule
