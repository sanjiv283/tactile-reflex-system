`timescale 1ns/1ps
module tb_pwm_generator;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [7:0] duty = 0; reg kill = 0; wire pwm;
    pwm_generator dut (.clk(clk), .rst_n(rst_n), .duty(duty), .kill(kill), .pwm_out(pwm));
    integer pass = 0, fail = 0, hi, i, t;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task measure(output integer h); integer n; begin h = 0; for (n = 0; n < 4096; n = n + 1) begin @(posedge clk); if (pwm) h = h + 1; end end endtask
    initial begin
        repeat (3) @(posedge clk); rst_n = 1;
        duty = 8'd0;   repeat (4096) @(posedge clk); measure(hi); check(hi == 0, "duty 0 -> output always low");
        duty = 8'd128; repeat (4096) @(posedge clk); measure(hi); check(hi == 2048, "duty 128 -> 50 percent");
        duty = 8'd180; repeat (4096) @(posedge clk); measure(hi); check(hi == 2880, "duty 180 -> 2880 of 4096 clocks");
        duty = 8'd255; repeat (4096) @(posedge clk); measure(hi); check(hi == 4080, "duty 255 -> 4080 of 4096 clocks");
        // duty change is applied only at the period boundary
        duty = 8'd64; measure(hi); check(hi == 4080 || hi == 1024 || (hi > 1024 && hi < 4080), "update lands within one period");
        duty = 8'd64; repeat (4096) @(posedge clk); measure(hi); check(hi == 1024, "duty 64 -> 1024 of 4096");
        // kill acts within one clock regardless of duty
        duty = 8'd255; repeat (4096) @(posedge clk); while (!pwm) @(posedge clk);
        @(negedge clk); kill = 1; @(posedge clk); @(posedge clk); #1 check(pwm == 0, "kill forces output low within 2 clocks");
        for (i = 0; i < 100; i = i + 1) begin @(posedge clk); if (pwm) fail = fail + 1; end
        kill = 0; rst_n = 0; @(posedge clk); @(posedge clk); #1 check(pwm == 0, "reset -> low");
        $display("TB tb_pwm_generator: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
