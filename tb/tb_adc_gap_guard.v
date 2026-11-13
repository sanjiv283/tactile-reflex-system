`timescale 1ns/1ps
// Accepted-configuration check for the ADC_GAP guard. Compile with -Ptb_adc_gap_guard.GAP=<n> -Ptb_adc_gap_guard.IDLE=<0|1>.
// Invalid settings must fail to elaborate (see sim/check_adc_gap_guard.sh); valid ones must show frame period = GAP + 96 clocks.
module tb_adc_gap_guard #(parameter GAP = 8, parameter IDLE = 0);
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    wire cs_n, sclk, m; wire [11:0] sample; wire sv, fe;
    ad7476_model #(.IDLE_HI(1)) adc (.cs_n(cs_n), .sclk(sclk), .value(12'h123), .corrupt(1'b0), .miso(m));
    adc_interface #(.GAP(GAP), .IDLE_CHK(IDLE)) dut (.clk(clk), .rst_n(rst_n), .adc_miso(m), .adc_cs_n(cs_n), .adc_sclk(sclk),
        .sample(sample), .sample_valid(sv), .frame_err(fe));
    integer cyc = 0, t1, t2, t3, pass = 0, fail = 0; always @(posedge clk) cyc <= cyc + 1;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    initial begin
        repeat (4) @(posedge clk); rst_n = 1;
        @(posedge sv); t1 = cyc; @(posedge sv); t2 = cyc; @(posedge sv); t3 = cyc;
        check(t2 - t1 == GAP + 96 && t3 - t2 == GAP + 96, "frame period = GAP + 96 clocks");
        check(sample === 12'h123 && fe === 1'b0, "sample decoded, no frame error");
        $display("INFO gap=%0d idle_chk=%0d frame_period=%0d", GAP, IDLE, t2 - t1);
        $display("TB tb_adc_gap_guard: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #20_000_000; $display("TB tb_adc_gap_guard: TIMEOUT"); $finish; end
endmodule
