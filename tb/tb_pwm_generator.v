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
        // EXACT boundary behaviour: align to a period start, change the duty in the middle of a period
        duty = 8'd200; repeat (8192) @(posedge clk); @(posedge clk); while (dut.cnt != 12'd0) @(posedge clk);
        hi = 0; for (i = 0; i < 4096; i = i + 1) begin if (i == 2048) duty = 8'd10; @(posedge clk); if (pwm) hi = hi + 1; end
        check(hi == 3200, "duty changed in the MIDDLE of a period: that period still uses the old duty (200 -> 3200 clocks high)");
        measure(hi); check(hi == 160, "the new duty (10 -> 160 clocks high) applies from the next period");
        duty = 8'd200; repeat (8192) @(posedge clk); @(posedge clk); #1; while (dut.cnt != 12'd4000) begin @(posedge clk); #1; end duty = 8'd0;
        while (dut.cnt != 12'hFFF) begin @(posedge clk); #1; end check(dut.duty_active == 8'd200, "command 0 issued late in the period: the active duty is still 200 at the last count");
        @(posedge clk); #1 check(dut.duty_active == 8'd0, "the new duty is loaded exactly at the period boundary");
        // kill acts within one clock regardless of duty
        duty = 8'd255; repeat (4096) @(posedge clk); while (!pwm) @(posedge clk);
        @(negedge clk); kill = 1; @(posedge clk); @(posedge clk); #1 check(pwm == 0, "kill forces output low within 2 clocks");
        for (i = 0; i < 100; i = i + 1) begin @(posedge clk); if (pwm) fail = fail + 1; end
        kill = 0; rst_n = 0; @(posedge clk); @(posedge clk); #1 check(pwm == 0, "reset -> low");
        $display("TB tb_pwm_generator: PASS %0d FAIL %0d VECTORS 0 NOTE directed assertions only", pass, fail); $finish;
    end
endmodule
