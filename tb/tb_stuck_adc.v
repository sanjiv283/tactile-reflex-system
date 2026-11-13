`timescale 1ns/1ps
// ADC line diagnostics: legitimate zero force, normal variation, stuck-low, disconnected (pulled-up), single glitch,
// advisory zero_run. Core with IDLE_CHK=1, ADC_GAP=64 and a model whose MISO idles high (pull-up) when CS is high.
module tb_stuck_adc;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'h000; reg fclr = 0; reg [1:0] mode = 0;          // mode 0 = ADC, 1 = MISO forced low, 2 = forced high
    wire cs_n, sclk, m_adc, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov, zrun; wire [7:0] cmd; wire [4:0] trip; wire [11:0] fo;
    wire miso = (mode == 1) ? 1'b0 : (mode == 2) ? 1'b1 : m_adc;
    ad7476_model #(.IDLE_HI(1)) adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(1'b0), .miso(m_adc));
    tactile_reflex_top #(.PRED_EN(0), .ADC_GAP(64), .IDLE_CHK(1), .ZERO_FRAMES(20)) dut (.clk(clk), .rst_n(rst_n),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso), .estop_n(1'b1), .fault_clear(fclr), .ai_gpio(16'd0), .pwm_out(pwm),
        .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a), .ai_valid(ai_v), .dbg_sample_valid(dbg_sv),
        .force_out(fo), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov), .zero_run(zrun));

    integer pass = 0, fail = 0, i;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task frames(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) begin @(posedge clk); while (!dbg_sv) @(posedge clk); end end endtask
    task clear_faults; begin @(negedge clk); fclr = 1; repeat (8) @(negedge clk); fclr = 0; repeat (4) @(negedge clk); end endtask
    task settle_pwm; begin frames(6); repeat (8192) @(posedge clk); end endtask
    task pwm_high(output integer h); integer n; begin h = 0; for (n = 0; n < 4096; n = n + 1) begin @(posedge clk); if (pwm) h = h + 1; end end endtask
    integer h;

    initial begin
        repeat (6) @(posedge clk); rst_n = 1; frames(4); clear_faults; frames(3);
        // ---- A. legitimate zero force: not a fault, drives the approach command, advisory flag only after ZERO_FRAMES ----
        value = 12'd0; frames(8);
        check(safe === 1'b0 && sfault === 1'b0 && cmd === 8'd180, "A: zero force is legitimate: no fault, approach command");
        check(zrun === 1'b0, "A: zero_run not yet set after 8 zero frames");
        frames(30); settle_pwm; pwm_high(h);
        check(zrun === 1'b1, "A: zero_run (advisory) set after a long run of zeros");
        check(safe === 1'b0 && sfault === 1'b0 && cmd === 8'd180 && h == 180 * 16, "A: zero_run never trips or changes the command");
        // ---- B. normal variation ----
        value = 12'd3; frames(3); check(safe === 1'b0 && sfault === 1'b0 && zrun === 1'b0, "B: code 3: normal, zero_run clears");
        value = 12'd40; frames(3); check(safe === 1'b0 && cmd === 8'd180, "B: code 40: normal, LUT approach command");
        value = 12'h1F4; frames(3); check(safe === 1'b0 && sfault === 1'b0, "B: code 500: normal");
        value = 12'h9FF; frames(3); check(safe === 1'b0, "B: 0x9FF below FORCE_MAX");
        value = 12'hA00; frames(3); check(safe === 1'b1 && trip[0] === 1'b1 && sfault === 1'b0, "B: FORCE_MAX trips (force limit, not sensor fault)");
        value = 12'd0; frames(3); check(safe === 1'b0 && sfault === 1'b0, "B: back to zero: released, not a fault");
        // ---- C. single glitch on the idle line: that frame is invalid, no latch ----
        @(posedge cs_n); mode = 1; @(negedge cs_n); #1 mode = 0; frames(3);
        check(sfault === 1'b0 && safe === 1'b0, "C: one idle-low frame does not latch a fault and recovers");
        // ---- D. K-1 = 3 bad frames: still no latch ----
        mode = 1; frames(3); check(sfault === 1'b0, "D: 3 stuck-low frames: below the latch limit"); mode = 0; frames(3);
        check(sfault === 1'b0 && safe === 1'b0, "D: line recovers, no latch");
        // ---- E. stuck-low ADC line (valid zero frames, idle low) ----
        mode = 1; frames(2); check(safe === 1'b1 && trip[3] === 1'b1, "E: stuck low: frames invalid, safe state");
        frames(4); check(sfault === 1'b1, "E: stuck low: sensor fault latched within 6 frames");
        repeat (400) @(posedge clk); pwm_high(h); check(h == 0, "E: stuck low: PWM stays low");
        mode = 0; frames(3); check(sfault === 1'b1 && safe === 1'b1, "E: fault stays latched after the line recovers");
        clear_faults; frames(3); check(sfault === 1'b0 && safe === 1'b0, "E: operator clear after recovery");
        // ---- F. disconnected ADC: MISO pulled high ----
        mode = 2; frames(6); check(sfault === 1'b1 && safe === 1'b1, "F: disconnected (pull-up, all ones): sensor fault");
        mode = 0; frames(3); clear_faults; frames(3); check(sfault === 1'b0 && safe === 1'b0, "F: reconnect and clear");
        // ---- G. reset clears everything ----
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1; frames(4); check(zrun === 1'b0, "G: reset clears zero_run");
        $display("TB tb_stuck_adc: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #80_000_000; $display("TB tb_stuck_adc: TIMEOUT"); $finish; end
endmodule
