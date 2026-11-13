`timescale 1ns/1ps
// T-3 board level (T12): DE2-115 wrapper with the PRODUCTION clear debounce (CLR_DB=50000 clocks = 1 ms at 50 MHz).
// KEY[1] is held through KEY[3] reset; short presses are ignored; a full 1 ms release then a full 1 ms press clears.
module tb_fault_clear_de2;
    reg clk = 0; always #10 clk = ~clk;
    reg [3:0] key = 4'b1111; reg uart_rxd = 1;
    wire [17:0] ledr; wire [8:0] ledg; wire uart_txd, cs_n, sclk, miso, pwm, dsv, dsafe;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(12'h100), .corrupt(1'b0), .miso(miso));
    de2_115_top #(.CLKS_PER_BIT(16), .TX_PERIOD(3000), .AI_TIMEOUT(20000), .PRED_EN(0)) dut (.CLOCK_50(clk), .KEY(key), .LEDR(ledr), .LEDG(ledg),
        .UART_RXD(uart_rxd), .UART_TXD(uart_txd), .ADC_CS_N(cs_n), .ADC_SCLK(sclk), .ADC_MISO(miso), .ESTOP_EXT_N(1'b1),
        .PWM_OUT(pwm), .DBG_SAMPLE_VALID(dsv), .DBG_SAFE_STATE(dsafe));
    wire safe = ledr[0], estop = ledr[2];
    integer pass = 0, fail = 0, h, k;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task count_pwm(input integer cycles, output integer hi); begin hi = 0; for (k = 0; k < cycles; k = k + 1) begin @(posedge clk); if (pwm) hi = hi + 1; end end endtask
    initial begin
        check(dut.CLR_DB == 50000 && dut.u_core.u_fault.CLR_DB == 50000, "wrapper default CLR_DB = 50000 clocks (1 ms) reaches the fault handler");
        // KEY[1] pressed (low) before and through the KEY[3] reset
        key[1] = 0; key[3] = 0; repeat (8) @(posedge clk); key[3] = 1;
        repeat (300000) @(posedge clk);
        check(estop === 1'b1 && safe === 1'b1, "T12: KEY[1] held through reset: e-stop latched and safe after 6 ms");
        count_pwm(20000, h); check(h == 0, "T12: PWM stays low while KEY[1] is held");
        // release for 1.2 ms (armed), then a press shorter than 1 ms: ignored
        key[1] = 1; repeat (60000) @(posedge clk); key[1] = 0; repeat (40000) @(posedge clk); key[1] = 1; repeat (2000) @(posedge clk);
        check(estop === 1'b1 && safe === 1'b1, "T12: press of 0.8 ms (< 1 ms): ignored");
        // release too short (0.8 ms) before a long press: not armed, ignored
        repeat (38000) @(posedge clk); key[1] = 0; repeat (70000) @(posedge clk);
        check(estop === 1'b1 && safe === 1'b1, "T12: press after a release shorter than 1 ms: ignored");
        // full release 1.2 ms, then a full press 1.2 ms: clears
        key[1] = 1; repeat (60000) @(posedge clk); key[1] = 0; repeat (60000) @(posedge clk);
        repeat (3000) @(posedge clk);
        check(estop === 1'b0 && safe === 1'b0, "T12: 1.2 ms release then 1.2 ms press clears and releases the safe state");
        key[1] = 1; repeat (2000) @(posedge clk); count_pwm(8192, h); check(h > 0, "T12: PWM runs after the clear");
        $display("TB tb_fault_clear_de2: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #200_000_000; $display("TB tb_fault_clear_de2: TIMEOUT"); $finish; end
endmodule
