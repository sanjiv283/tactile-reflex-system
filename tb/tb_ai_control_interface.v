`timescale 1ns/1ps
module tb_ai_control_interface;
    reg clk = 0, rst_n = 0; always #5 clk = ~clk;
    reg [15:0] g = 0; wire [1:0] cls; wire v;
    ai_control_interface #(.TIMEOUT(40)) dut (.clk(clk), .rst_n(rst_n), .gpio(g), .ai_class(cls), .ai_valid(v));
    integer pass = 0, fail = 0; reg [7:0] hb = 0;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task send(input [1:0] c, input okflag, input good_inv); begin @(negedge clk); hb = hb + 1; g = {hb, 1'b0, okflag, good_inv ? ~c : c, 2'b00, c}; repeat (4) @(negedge clk); end endtask
    initial begin
        repeat (3) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
        check(v == 0, "invalid at start: no heartbeat yet");
        send(2'd2, 1, 1); check(v == 1 && cls == 2'd2, "valid result accepted");
        send(2'd3, 1, 1); check(v == 1 && cls == 2'd3, "class change follows");
        send(2'd1, 0, 1); check(v == 0, "PS valid flag clear -> invalid");
        send(2'd1, 1, 0); check(v == 0, "class/inverse mismatch -> invalid");
        send(2'd0, 1, 1); check(v == 1 && cls == 2'd0, "recovers with a good message");
        repeat (60) @(negedge clk); check(v == 0, "heartbeat stalls -> invalid (AI failure)");
        send(2'd2, 1, 1); check(v == 1, "heartbeat resumes -> valid");
        rst_n = 0; @(posedge clk); @(posedge clk); #1 check(v == 0, "reset -> invalid");
        $display("TB tb_ai_control_interface: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
