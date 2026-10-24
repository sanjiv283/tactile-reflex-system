`timescale 1ns/1ps
module tb_safety_governor;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg iv = 0; reg [11:0] fc = 0; reg [7:0] lc = 8'd104; reg ainv = 0, sf = 0, es = 0, aiv = 0; reg [1:0] aic = 0;
    wire [7:0] cmd; wire safe, aiu, aio; wire [3:0] tr;
    safety_governor dut (.clk(clk), .rst_n(rst_n), .in_valid(iv), .force_code(fc), .lut_cmd(lc), .adc_invalid(ainv), .sensor_fault(sf),
        .estop_active(es), .ai_valid(aiv), .ai_class(aic), .cmd_out(cmd), .safe_state(safe), .trip_reason(tr), .ai_used(aiu), .ai_overridden(aio));
    integer pass = 0, fail = 0;
    task check(input c, input [255:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: %0s", msg); end end endtask
    task step(input [11:0] f, input [7:0] l); begin @(negedge clk); fc = f; lc = l; iv = 1; @(negedge clk); iv = 0; @(negedge clk); end endtask
    initial begin
        repeat (3) @(posedge clk);
        check(safe == 1 && cmd == 0, "safe state during reset");
        rst_n = 1; repeat (2) @(posedge clk); #1 check(safe == 1, "stays safe until first valid sample (not armed)");
        step(12'h400, 8'd104); check(safe == 0 && cmd == 8'd104, "FPGA-only: command follows LUT");
        aiv = 1; aic = 0; step(12'h400, 8'd104); check(cmd == 8'd104, "AI class 0 does not change command");
        aic = 1; step(12'h400, 8'd104); check(cmd == 8'd104, "AI class 1 does not change command");
        aic = 2; step(12'h400, 8'd104); check(cmd == 8'd64, "AI class 2 caps command at HOLD_CAP");
        aic = 3; step(12'h400, 8'd104); check(cmd == 8'd24, "AI class 3 caps command at EXCESS_CAP");
        aic = 3; step(12'h400, 8'd10);  check(cmd == 8'd10, "AI never raises the command");
        aic = 2; step(12'h400, 8'd30);  check(cmd == 8'd30, "AI class 2 never raises a low LUT command");
        aiv = 0; aic = 3; step(12'h400, 8'd104); check(cmd == 8'd104, "invalid AI ignored (FPGA-only)");
        // max force with AI claiming normal grip
        aiv = 1; aic = 2; step(12'h9FF, 8'd1); check(safe == 0, "just below FORCE_MAX is not tripped");
        step(12'hA00, 8'd0); check(safe == 1 && cmd == 0 && tr[0] == 1, "FORCE_MAX trips safe state");
        check(aio == 1, "AI 'normal grip' overridden by hard limit");
        aic = 3; step(12'hA00, 8'd0); check(aio == 0, "no override flag when AI also predicted excess");
        step(12'h950, 8'd0); check(safe == 1, "hysteresis: still safe between REL and MAX");
        step(12'h8FF, 8'd30); check(safe == 0 && cmd != 0, "releases below FORCE_REL");
        // other hard limits
        sf = 1; step(12'h400, 8'd104); check(safe == 1 && tr[1] == 1 && cmd == 0, "sensor fault trips");
        sf = 0; es = 1; step(12'h400, 8'd104); check(safe == 1 && tr[2] == 1, "e-stop trips");
        es = 0; ainv = 1; step(12'h400, 8'd104); check(safe == 1 && tr[3] == 1, "invalid ADC trips");
        ainv = 0; aiv = 1; aic = 0; step(12'h400, 8'd104); check(safe == 0 && cmd == 8'd104, "recovers when causes clear");
        es = 1; @(negedge clk); @(posedge clk); @(posedge clk); #1 check(safe == 1, "e-stop acts without a new sample (level-sensitive)");
        es = 0; rst_n = 0; @(posedge clk); @(posedge clk); #1 check(safe == 1 && cmd == 0, "reset forces safe state");
        $display("TB tb_safety_governor: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
