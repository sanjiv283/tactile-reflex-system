`timescale 1ns/1ps
// Replays ML test-set vectors (SIMULATED ADC counts + the decision tree's class) through the full RTL.
// Invariants checked on every ADC sample:
//   1. force >= FORCE_MAX  ->  safe state and PWM low, whatever class the AI sent
//   2. command never exceeds the LUT command (AI can only lower it)
module tb_replay;
    reg clk = 0, rst_n = 0; always #5 clk = ~clk;
    reg [11:0] value = 12'h000;
    reg [7:0] hb = 0; reg [8:0] hbc = 0; reg [1:0] ps_cls = 0;
    wire [15:0] ai_gpio = {hb, 1'b0, 1'b1, ~ps_cls, 2'b00, ps_cls};
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [3:0] trip;
    reg fault_clear = 0;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(1'b0), .miso(miso));
    tactile_reflex_top #(.AI_TIMEOUT(3000)) dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso),
        .estop_n(1'b1), .fault_clear(fault_clear), .ai_gpio(ai_gpio), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault),
        .estop_active(estop_a), .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));
    reg [7:0] rom [0:255]; initial $readmemh("rtl/force_lut.mem", rom);
    reg [15:0] vec [0:2047];
    always @(posedge clk) begin hbc <= hbc + 1; if (hbc == 499) begin hbc <= 0; hb <= hb + 1; end end

    integer n, i, viol_safe = 0, viol_cmd = 0, over_samples = 0, overridden = 0, ai_wrong_but_safe = 0, checked = 0, tripped = 0;
    reg [11:0] f; reg adv;
    initial begin
        adv = $test$plusargs("ADVERSARIAL");   // AI always claims class 2 (normal grip)
        $readmemh("tb/replay_vectors.mem", vec);
        n = 0; while (n < 2048 && vec[n] !== 16'hxxxx) n = n + 1;
        repeat (5) @(posedge clk); rst_n = 1; repeat (2000) @(posedge clk);
        @(negedge clk); fault_clear = 1; repeat (8) @(negedge clk); fault_clear = 0;
        for (i = 0; i < n; i = i + 1) begin
            value = vec[i][11:0]; ps_cls = adv ? 2'd2 : vec[i][13:12];
            // wait for the frame that carries this value, then 6 cycles for the pipeline
            @(posedge clk); while (!dbg_sv) @(posedge clk);
            @(posedge clk); while (!dbg_sv) @(posedge clk);
            repeat (6) @(posedge clk); #1;
            f = dut.force_code; checked = checked + 1;
            if (safe) tripped = tripped + 1;
            if (f >= 12'hA00) begin
                over_samples = over_samples + 1;
                if (!(safe === 1'b1 && pwm === 1'b0 && cmd === 8'd0)) viol_safe = viol_safe + 1;
                if (ps_cls != 2'd3) overridden = overridden + 1;
            end
            if (cmd > rom[f >> 4]) viol_cmd = viol_cmd + 1;
        end
        $display("RESULT replay mode=%0s vectors=%0d over_limit_samples=%0d ai_not_class3_during_over_limit=%0d safe_state_samples=%0d", adv ? "adversarial_ai" : "ml_tree_ai", checked, over_samples, overridden, tripped);
        $display("RESULT replay mode=%0s violations: safe_state=%0d cmd_above_lut=%0d", adv ? "adversarial_ai" : "ml_tree_ai", viol_safe, viol_cmd);
        $display("TB tb_replay%0s: PASS %0d FAIL %0d", adv ? "_adversarial" : "", (viol_safe == 0 && viol_cmd == 0) ? 2 : 0, viol_safe + viol_cmd);
        $finish;
    end
    initial begin #400_000_000; $display("TB tb_replay: TIMEOUT"); $finish; end
endmodule
