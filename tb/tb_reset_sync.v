`timescale 1ns/1ps
// T-2: the whole board wrapper must see ONE reset: KEY[3] synchronised in the core (async assert, synchronous release).
// The UART bridge and telemetry must use that same reset, so their release is always clock-aligned.
// KEY[3] is toggled at every phase offset of the 20 ns clock; released at 1 ns steps, never on a clock edge.
module tb_reset_sync;
    reg clk = 0; always #10 clk = ~clk;
    localparam CPB = 16;
    reg [3:0] key = 4'b1111; reg uart_rxd = 1; reg [11:0] value = 12'h000;
    wire [17:0] ledr; wire [8:0] ledg; wire uart_txd, cs_n, sclk, miso, pwm, dsv, dsafe;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(1'b0), .miso(miso));
    de2_115_top #(.CLKS_PER_BIT(CPB), .TX_PERIOD(3000), .AI_TIMEOUT(20000), .PRED_EN(0), .CLR_DB(2)) dut (.CLOCK_50(clk), .KEY(key), .LEDR(ledr), .LEDG(ledg),
        .UART_RXD(uart_rxd), .UART_TXD(uart_txd), .ADC_CS_N(cs_n), .ADC_SCLK(sclk), .ADC_MISO(miso), .ESTOP_EXT_N(1'b1),
        .PWM_OUT(pwm), .DBG_SAMPLE_VALID(dsv), .DBG_SAFE_STATE(dsafe));
    integer pass = 0, fail = 0, i, bad_rel = 0, mism = 0, nrel = 0;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task frames(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) begin @(posedge clk); while (!dsv) @(posedge clk); end end endtask
    task tx_byte(input [7:0] b); integer k; begin uart_rxd = 0; repeat (CPB) @(posedge clk); for (k = 0; k < 8; k = k + 1) begin uart_rxd = b[k]; repeat (CPB) @(posedge clk); end uart_rxd = 1; repeat (CPB) @(posedge clk); end endtask

    // 1. all three blocks must always see the same reset level
    wire r_core = dut.u_core.rst_s, r_br = dut.u_bridge.rst_n, r_tx = dut.u_tele.rst_n;
    always @(r_core or r_br or r_tx) begin #0.001; if (!(r_core === r_br && r_core === r_tx)) mism = mism + 1; end
    // 2. every release of the shared reset must be clock-aligned: it must happen in the same time step as a clk rising edge
    time t_clk = 0; always @(posedge clk) t_clk = $time;
    always @(posedge r_core) begin nrel = nrel + 1; if ($time !== t_clk) bad_rel = bad_rel + 1; end

    initial begin
        repeat (10) @(posedge clk); #3 key[3] = 0; repeat (6) @(posedge clk);
        // sweep release phases 1..19 ns after a clock edge (never exactly on an edge)
        for (i = 1; i < 20; i = i + 1) begin
            key[3] = 0; repeat (4) @(posedge clk); #(i) key[3] = 1; repeat (5) @(posedge clk);
            // reset again at a different phase, with the 2-flop release still in progress
            #(20 - i) key[3] = 0; #(i) key[3] = 1; repeat (6) @(posedge clk);
        end
        check(nrel >= 38, "reset released at least 38 times");
        check(bad_rel == 0, "every reset release is aligned with a clk rising edge");
        check(mism == 0, "core, UART bridge and telemetry always see the same reset level");
        // glitch pulses shorter than a clock: asynchronous assert must still reset everything
        #4 key[3] = 0; #2 key[3] = 1; repeat (6) @(posedge clk);
        check(mism == 0 && bad_rel == 0, "sub-clock KEY[3] glitch: still one aligned reset");
        // after the last release the system must work: operator clear, AI packet over UART, telemetry out
        repeat (4) @(posedge clk); frames(3);
        check(dut.u_bridge.ai_gpio === 16'd0, "bridge idle word after reset");
        key[1] = 0; repeat (10) @(posedge clk); key[1] = 1; frames(6);
        check(ledr[0] === 1'b0 && ledr[2] === 1'b0, "operator clear releases the safe state after the reset sweep");
        tx_byte(8'hA5); tx_byte({3'b000, 1'b1, 2'b11, 2'b00}); tx_byte(~{3'b000, 1'b1, 2'b11, 2'b00}); repeat (200) @(posedge clk);
        check(dut.u_bridge.ai_gpio[6] === 1'b1 && dut.u_bridge.ai_gpio[15:8] === 8'd1, "UART packet accepted after reset sweep (heartbeat 1)");
        $display("INFO releases=%0d misaligned=%0d mismatches=%0d", nrel, bad_rel, mism);
        $display("TB tb_reset_sync: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #50_000_000; $display("TB tb_reset_sync: TIMEOUT"); $finish; end
endmodule
