`timescale 1ns/1ps
module tb_adc_interface;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'h000; reg corrupt = 0;
    wire cs_n, sclk, miso, sv, ferr; wire [11:0] sample;
    ad7476_model m (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    adc_interface dut (.clk(clk), .rst_n(rst_n), .adc_miso(miso), .adc_cs_n(cs_n), .adc_sclk(sclk), .sample(sample), .sample_valid(sv), .frame_err(ferr));
    integer pass = 0, fail = 0, cyc = 0, t_prev = 0, period = 0, k;
    always @(posedge clk) cyc <= cyc + 1;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = pass * 0 + fail + 1; $display("FAIL: %0s", msg); end end endtask
    task wait_sv; begin @(posedge clk); while (!sv) @(posedge clk); end endtask
    reg [11:0] vals [0:5];
    initial begin
        vals[0]=12'h000; vals[1]=12'h001; vals[2]=12'h5A5; vals[3]=12'hA00; vals[4]=12'hFEF; vals[5]=12'h800;
        repeat (4) @(posedge clk); rst_n = 1;
        check(cs_n === 1'b1 && sclk === 1'b1, "idle CS high, SCLK high");
        for (k = 0; k < 6; k = k + 1) begin
            value = vals[k]; wait_sv; wait_sv;                 // second frame is guaranteed to hold the new value
            check(sample === vals[k], "sample matches ADC value");
            check(ferr === 1'b0, "no frame error");
        end
        wait_sv; t_prev = cyc; wait_sv; period = cyc - t_prev;
        $display("INFO: ADC frame period = %0d clk cycles (%0d ns at 50 MHz)", period, period * 20);
        check(period == 104, "frame period is 104 clocks");
        corrupt = 1; wait_sv; wait_sv; check(ferr === 1'b1, "frame error flagged when leading bit is not zero");
        corrupt = 0; wait_sv; wait_sv; check(ferr === 1'b0, "frame error clears");
        rst_n = 0; repeat (3) @(posedge clk); check(cs_n === 1'b1 && sv === 1'b0, "reset returns to idle");
        $display("TB tb_adc_interface: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
