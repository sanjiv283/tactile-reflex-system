`timescale 1ns/1ps
// CLR_DB guard / width check for fault_handler. Compile with -Ptb_clr_db_guard.DB=<n>. Invalid values (< 2) must fail to elaborate
// (see sim/check_clr_db_guard.sh). Valid values must give counter width ceil(log2(DB+1)) and the exact request timing:
// a press of DB-1 cycles gives no request, a press of DB cycles gives exactly one request, preceded by a release of DB cycles.
module tb_clr_db_guard #(parameter DB = 2);
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg fcl = 0; wire sf, ea; wire [2:0] code;
    fault_handler #(.WD_CYCLES(60000), .INVALID_LIMIT(4), .CLR_DB(DB)) dut (.clk(clk), .rst_n(rst_n), .sample_valid(1'b1), .adc_invalid(1'b0),
        .estop_n(1'b1), .fault_clear(fcl), .sensor_fault(sf), .estop_active(ea), .fault_code(code));
    integer pass = 0, fail = 0, nreq = 0, exp_w, v, k;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task tick(input integer n); begin repeat (n) @(negedge clk); end endtask
    always @(posedge clk) if (dut.clr_req) nreq <= nreq + 1;
    initial begin
        exp_w = 0; for (k = DB; k > 0; k = k >> 1) exp_w = exp_w + 1;   // bits needed to represent DB itself
        check(dut.RW == exp_w, "counter width = bits needed to represent CLR_DB");
        $display("INFO CLR_DB=%0d counter_width=%0d", DB, dut.RW);
        tick(3); rst_n = 1;
        fcl = 0; tick(DB - 1); fcl = 1; tick(DB + 2);             // release one cycle short of CLR_DB: not armed, press ignored
        check(nreq == 0, "release of CLR_DB-1 cycles: not armed, no request");
        fcl = 0; tick(DB + 2); fcl = 1; tick(DB - 1); fcl = 0; tick(DB + 2);   // armed, press one cycle short
        check(nreq == 0, "press of CLR_DB-1 cycles: no request");
        fcl = 1; tick(DB + 5);                                      // armed again by the release above: a stable press of CLR_DB
        check(nreq == 1, "release then press of CLR_DB: exactly one request");
        tick(DB + 5); check(nreq == 1, "held: still one request");
        $display("TB tb_clr_db_guard: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #400_000_000; $display("TB tb_clr_db_guard: TIMEOUT"); $finish; end
endmodule
