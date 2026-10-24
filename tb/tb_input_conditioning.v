`timescale 1ns/1ps
module tb_input_conditioning;
    reg clk = 0, rst_n = 0; always #5 clk = ~clk;
    reg [11:0] sample = 0; reg sv = 0, ferr = 0; wire [11:0] fc; wire fv, inv;
    input_conditioning dut (.clk(clk), .rst_n(rst_n), .sample(sample), .sample_valid(sv), .frame_err(ferr), .force_code(fc), .force_valid(fv), .adc_invalid(inv));
    integer pass = 0, fail = 0;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task push(input [11:0] s, input fe); begin @(negedge clk); sample = s; ferr = fe; sv = 1; @(negedge clk); sv = 0; @(negedge clk); end endtask
    initial begin
        repeat (3) @(posedge clk); rst_n = 1;
        push(12'h000, 0); check(fc == 12'h000 && inv == 0, "zero is a valid reading (no contact)");
        push(12'h123, 0); check(fc == 12'h123 && inv == 0, "normal value passes through");
        push(12'hFEF, 0); check(inv == 0, "just below rail is valid");
        push(12'hFF0, 0); check(inv == 1, "rail threshold is invalid");
        push(12'hFFF, 0); check(inv == 1, "full scale is invalid");
        push(12'h200, 1); check(inv == 1, "frame error is invalid");
        push(12'h200, 0); check(inv == 0, "recovers on a good sample");
        @(negedge clk); sample = 12'h777; @(negedge clk); check(fc == 12'h200, "holds value without valid strobe");
        rst_n = 0; @(posedge clk); @(posedge clk); check(fc == 0 && fv == 0 && inv == 0, "reset clears outputs");
        $display("TB tb_input_conditioning: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
