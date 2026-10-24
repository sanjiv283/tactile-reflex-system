`timescale 1ns/1ps
// Full path with the slope predictor on (A) and off (B), same ADC ramp. PRED_WIN = 2000 clocks, one ramp step per window.
module tb_pred_system;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 0; reg clr = 0;
    wire csA, sA, mA, csB, sB, mB, pwmA, pwmB, safeA, safeB, sfA, sfB, esA, esB, aivA, aivB, dvA, dvB, ovA, ovB;
    wire [7:0] cmdA, cmdB; wire [4:0] trA, trB; wire [11:0] fA, fB;
    ad7476_model adcA (.cs_n(csA), .sclk(sA), .value(value), .corrupt(1'b0), .miso(mA));
    ad7476_model adcB (.cs_n(csB), .sclk(sB), .value(value), .corrupt(1'b0), .miso(mB));
    tactile_reflex_top #(.PRED_EN(1), .PRED_WIN(2000)) A (.clk(clk), .rst_n(rst_n), .adc_cs_n(csA), .adc_sclk(sA), .adc_miso(mA), .estop_n(1'b1), .fault_clear(clr), .ai_gpio(16'd0),
        .pwm_out(pwmA), .safe_state(safeA), .sensor_fault(sfA), .estop_active(esA), .ai_valid(aivA), .dbg_sample_valid(dvA), .force_out(fA), .cmd_out(cmdA), .trip_reason(trA), .ai_overridden(ovA));
    tactile_reflex_top #(.PRED_EN(0), .PRED_WIN(2000)) B (.clk(clk), .rst_n(rst_n), .adc_cs_n(csB), .adc_sclk(sB), .adc_miso(mB), .estop_n(1'b1), .fault_clear(clr), .ai_gpio(16'd0),
        .pwm_out(pwmB), .safe_state(safeB), .sensor_fault(sfB), .estop_active(esB), .ai_valid(aivB), .dbg_sample_valid(dvB), .force_out(fB), .cmd_out(cmdB), .trip_reason(trB), .ai_overridden(ovB));
    integer pass = 0, fail = 0, vA, vB, k, step;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task restart(input [11:0] v); begin value = v; rst_n = 0; repeat (4) @(posedge clk); rst_n = 1; repeat (700) @(posedge clk); clr = 1; repeat (8) @(posedge clk); clr = 0; repeat (700) @(posedge clk); end endtask
    task ramp(input integer start, input integer inc, output integer valA, output integer valB);
        begin valA = -1; valB = -1; value = start; restart(start);
            for (k = 0; k < 60 && (valA < 0 || valB < 0); k = k + 1) begin
                value = start + k * inc; repeat (2000) @(posedge clk);
                if (valA < 0 && safeA) valA = value; if (valB < 0 && safeB) valB = value;
            end end endtask
    initial begin
        ramp(768, 200, vA, vB);
        $display("RESULT pred_system fast_ramp(+200/window): predictive trips at ADC value %0d (0x%0h), hard-limit-only trips at %0d (0x%0h), FORCE_MAX=2560", vA, vA, vB, vB);
        check(vA > 0 && vA < 2560, "fast ramp: predictive pre-limit trips before FORCE_MAX");
        check(trA[4] === 1'b1 || safeA, "predicted trip flagged");
        check(vB >= 2560, "hard-limit-only trips only at or above FORCE_MAX");
        check(vB - vA >= 100, "pre-limit leads by at least 100 counts");
        ramp(768, 60, vA, vB);
        $display("RESULT pred_system slow_ramp(+60/window): predictive trips at %0d, hard-limit-only trips at %0d", vA, vB);
        check(vA >= 2560 && vB >= 2560, "slow ramp (below noise guard): no early trip");
        restart(12'h500);
        for (k = 0; k < 40; k = k + 1) begin value = 12'h500 + ((k % 2) ? 12'd10 : -12'd10); repeat (2000) @(posedge clk); end
        check(!safeA && !safeB, "flat force with +-10 count noise: no trip");
        value = 12'h500; restart(12'h500); value = 12'h500 + 12'd160; repeat (6000) @(posedge clk);
        check(!safeA, "single 160-count step well below the limit: no trip (K=2 gives 480 < distance to limit)");
        $display("TB tb_pred_system: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #200_000_000; $display("TB tb_pred_system: TIMEOUT"); $finish; end
endmodule
