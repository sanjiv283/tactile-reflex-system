`timescale 1ns/1ps
// Frame-granular DROPOUT test (NEW; tb_frames.v is untouched). Same timing as tb_frames.v MODE 0, plus word bit 12 = sample ABSENT:
// absent frames force dut.force_valid low (the same technique tb_experiments.v uses). Run from the repository root.
module tb_frames_dropout;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'd400; reg corrupt = 0, estop_n = 1, fault_clear = 0;
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [4:0] trip; wire [11:0] fo;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    tactile_reflex_top dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso), .estop_n(estop_n),
        .fault_clear(fault_clear), .ai_gpio(16'd0), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a),
        .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .force_out(fo), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));
    reg [15:0] stim [0:4095]; reg [8*256-1:0] fn; reg [8*64-1:0] id; integer n, k, i;
    task apply(input [15:0] x); begin
        value = x[11:0]; corrupt = x[13]; estop_n = x[14]; fault_clear = x[15];
        if (x[12]) force dut.force_valid = 1'b0; else release dut.force_valid;
    end endtask
    task wait_sv; begin @(posedge clk); while (!dbg_sv) @(posedge clk); end endtask
    initial begin
        for (i = 0; i < 4096; i = i + 1) stim[i] = 16'hxxxx;
        if (!$value$plusargs("STIM=%s", fn) || !$value$plusargs("ID=%s", id)) begin $display("ERROR args"); $finish; end
        $readmemh(fn, stim); n = 0; while (stim[n] !== 16'hxxxx) n = n + 1;
        apply(stim[0]); repeat (6) @(posedge clk); rst_n = 1;
        for (k = 0; k < n; k = k + 1) begin
            wait_sv; repeat (4) @(negedge clk);
            $display("FRM,%0s,%0d,%0d,%0d,%0d,%0d,%0d", id, k, safe, cmd, trip, sfault, estop_a);
            @(negedge clk); if (k + 1 < n) apply(stim[k + 1]);
        end
        $finish;
    end
endmodule
