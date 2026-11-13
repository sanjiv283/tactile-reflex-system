`timescale 1ns/1ps
// T-3 fault_clear contract, unit level (fault_handler, CLR_DB=4): release-then-press, held button never clears,
// all-or-nothing, rejected requests are discarded. Covers T1, T2, T3, T4, T5, T6 (unit), T7, T8, and e-stop priority.
module tb_fault_clear;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    localparam DB = 4;
    reg sv = 0, inv = 0, es_n = 1, fcl = 0; wire sf, ea; wire [2:0] code;
    fault_handler #(.WD_CYCLES(60000), .INVALID_LIMIT(4), .CLR_DB(DB)) dut (.clk(clk), .rst_n(rst_n), .sample_valid(sv), .adc_invalid(inv),
        .estop_n(es_n), .fault_clear(fcl), .sensor_fault(sf), .estop_active(ea), .fault_code(code));
    integer pass = 0, fail = 0, i, c0;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task tick(input integer n); begin repeat (n) @(negedge clk); end endtask
    task rel(input integer n); begin fcl = 0; tick(n); end endtask
    task prs(input integer n); begin fcl = 1; tick(n); end endtask
    task smp(input bad); begin @(negedge clk); inv = bad; sv = 1; @(negedge clk); sv = 0; tick(2); end endtask
    task sensor_fault_on; begin smp(1); smp(1); smp(1); smp(1); end endtask     // persistent invalid: cause present
    // monitors: clr_req pulses, and any cycle where exactly one of two latched flags falls
    integer nreq = 0, partial = 0, wide = 0; reg pea = 0, psf = 0, preq = 0;
    always @(posedge clk) begin
        if (dut.clr_req) nreq <= nreq + 1;
        if (dut.clr_req && preq) wide <= wide + 1;                       // pulse must be one cycle wide
        if (pea && psf && ((pea && !ea) != (psf && !sf))) partial <= partial + 1;
        pea <= ea; psf <= sf; preq <= dut.clr_req;
    end
    initial begin
        tick(3); rst_n = 1; rel(10); smp(0); smp(0);
        check(sf === 0 && ea === 0 && nreq == 0, "start: healthy, no clear requests");
        // ---- T3: press while the cause is active: rejected; not remembered when the cause later disappears ----
        sensor_fault_on; check(sf === 1, "T3: persistent invalid latches sensor fault");
        rel(10); prs(12); check(sf === 1 && nreq == 1, "T3: press with cause active: request issued but rejected");
        smp(0); tick(20); check(sf === 1, "T3: cause disappears while button still held: NOT cleared (request not remembered)");
        rel(10); prs(12); check(sf === 0 && nreq == 2, "T3: release then fresh press after recovery clears");
        // ---- T1: clear already held when the fault occurs ----
        sensor_fault_on; smp(0); tick(100);
        check(sf === 1 && nreq == 2, "T1: clear held, fault occurs, cause disappears: stays latched");
        rel(10); prs(12); check(sf === 0 && nreq == 3, "T1: release and fresh press clears");
        // ---- T2: clear held through an e-stop press and release ----
        prs(12); es_n = 0; tick(4); check(ea === 1, "T2: e-stop latches while clear is held");
        es_n = 1; tick(100); check(ea === 1, "T2: e-stop released, clear still held: stays latched");
        rel(10); prs(12); check(ea === 0, "T2: release and fresh press clears the e-stop latch");
        // ---- T4: one clear per press, re-fault while still held stays latched ----
        sensor_fault_on; smp(0); rel(10); c0 = nreq;
        fcl = 1; tick(100);
        check(nreq - c0 == 1 && sf === 0, "T4: 100-cycle hold: exactly one clear request, fault cleared");
        sensor_fault_on; smp(0); tick(60);
        check(sf === 1 && nreq - c0 == 1, "T4: re-fault while still held: stays latched, no second request");
        rel(10);
        // ---- T5: short press, chatter, glitch ----
        c0 = nreq; prs(DB - 1); rel(10); check(sf === 1 && nreq == c0, "T5: press shorter than CLR_DB: no request");
        for (i = 0; i < 10; i = i + 1) begin fcl = 1; tick(1); fcl = 0; tick(1); end
        tick(10); check(sf === 1 && nreq == c0, "T5: chatter ending low: no request");
        fcl = 1; tick(1); fcl = 0; tick(1); fcl = 1; tick(2); fcl = 0; tick(1); fcl = 1; tick(12);
        check(sf === 1 && nreq == c0, "T5: press that starts with a bounce: no request (contract: a low sample during PRESS returns to WAIT)");
        rel(10); prs(12);
        check(sf === 0 && nreq == c0 + 1, "T5: full release then a stable press: exactly one request");
        rel(10);
        es_n = 0; tick(4); es_n = 1; rel(10); c0 = nreq;
        fcl = 1; tick(1); fcl = 0; tick(10);
        check(ea === 1 && nreq == c0, "T5: one-clock glitch with e-stop latched: no clear");
        // release bounce after a rejected press must not produce a second request
        smp(0); rel(10); es_n = 0; tick(4); prs(12); c0 = nreq;               // e-stop pressed + press: rejected request
        fcl = 0; tick(1); fcl = 1; tick(1); fcl = 0; tick(2); fcl = 1; tick(1); fcl = 0; tick(1); es_n = 1; fcl = 1; tick(20);
        check(ea === 1 && nreq == c0, "T5: release bounce / re-press without a full release: no new request");
        rel(10); prs(12); check(ea === 0, "T5: after a full release and press: clears");
        rel(10);
        // ---- T6 (unit): reset while clear is held, e-stop pressed; then fault while held ----
        fcl = 1; es_n = 0; rst_n = 0; tick(3); rst_n = 1; tick(60);
        check(ea === 1 && sf === 0, "T6: reset with clear held and e-stop pressed: e-stop latched");
        es_n = 1; tick(100); check(ea === 1, "T6: e-stop released while clear still held from before reset: stays latched");
        rel(10); prs(12); check(ea === 0, "T6: release and fresh press clears");
        fcl = 1; rst_n = 0; tick(3); rst_n = 1; tick(30); sensor_fault_on; smp(0); tick(60);
        check(sf === 1, "T6: clear held through reset, fault after reset, cause gone: stays latched");
        rel(10); prs(12); check(sf === 0, "T6: release and fresh press clears");
        rel(10);
        // ---- T8 / T7: all-or-nothing ----
        es_n = 0; sensor_fault_on; tick(4); check(ea === 1 && sf === 1, "T7: both latched");
        smp(0); rel(10); prs(12);
        check(ea === 1 && sf === 1, "T8: sensor recovered, e-stop still pressed: clear rejected (sensor latch kept too)");
        sensor_fault_on; es_n = 1; rel(10); prs(12);
        check(ea === 1 && sf === 1, "T8: e-stop released, sensor cause still present: clear rejected (e-stop latch kept too)");
        smp(0); rel(10); prs(12);
        check(ea === 0 && sf === 0 && partial == 0, "T7: all causes gone: both latches clear together");
        rel(10);
        // ---- e-stop and fault assertion are not delayed and win over a clear in the same cycle ----
        sensor_fault_on; smp(0); rel(10); fcl = 1; @(negedge clk); es_n = 0; @(posedge clk); #1;
        check(ea === 1, "e-stop asserts within 1 clock even while a clear request is being issued");
        check(partial == 0 && wide == 0, "no partial clears; clr_req is always one cycle wide");
        $display("INFO clear requests=%0d partial=%0d wide=%0d", nreq, partial, wide);
        $display("TB tb_fault_clear: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #50_000_000; $display("TB tb_fault_clear: TIMEOUT"); $finish; end
endmodule
