`timescale 1ns/1ps
module tb_fault_handler;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg sv = 0, inv = 0, es_n = 1, fcl = 0; wire sf, ea; wire [2:0] code;
    fault_handler #(.WD_CYCLES(50), .INVALID_LIMIT(4)) dut (.clk(clk), .rst_n(rst_n), .sample_valid(sv), .adc_invalid(inv), .estop_n(es_n), .fault_clear(fcl),
        .sensor_fault(sf), .estop_active(ea), .fault_code(code));
    integer pass = 0, fail = 0, i;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task sample(input bad); begin @(negedge clk); inv = bad; sv = 1; @(negedge clk); sv = 0; repeat (3) @(negedge clk); end endtask
    task clear; begin @(negedge clk); fcl = 1; repeat (2) @(negedge clk); fcl = 0; @(negedge clk); end endtask
    initial begin
        repeat (3) @(posedge clk); rst_n = 1;
        for (i = 0; i < 5; i = i + 1) sample(0); check(sf == 0 && ea == 0, "healthy: no faults");
        sample(1); sample(1); sample(1); check(sf == 0, "3 invalid samples: not yet a fault");
        sample(0); sample(1); sample(1); sample(1); check(sf == 0, "good sample resets the invalid counter");
        sample(1); check(sf == 1 && code[1] == 1, "4 consecutive invalid samples -> sensor fault");
        sample(0); check(sf == 1, "fault stays latched after cause clears");
        clear; check(sf == 0, "fault_clear releases once healthy");
        repeat (60) @(negedge clk); check(sf == 1 && code[0] == 1, "watchdog: no samples -> sensor fault");
        sample(0); clear; check(sf == 0, "recovers after samples resume and clear");
        @(negedge clk); es_n = 0; repeat (2) @(posedge clk); #1 check(ea == 1, "e-stop latches");
        @(negedge clk); es_n = 1; sample(0); check(ea == 1, "e-stop stays latched after release");
        clear; check(ea == 0, "e-stop clears only on fault_clear with the button released");
        @(negedge clk); es_n = 0; sample(0); clear; check(ea == 1, "fault_clear cannot clear a pressed e-stop"); es_n = 1; clear;
        @(negedge clk); es_n = 0; rst_n = 0; @(posedge clk); @(posedge clk); #1 check(ea == 1 && sf == 0, "reset: e-stop state follows the input");
        $display("TB tb_fault_handler: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
