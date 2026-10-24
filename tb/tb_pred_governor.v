`timescale 1ns/1ps
// RTL slope predictor vs the Python reference model (ml/pred_eval.py): 4720 vectors, one per window (PRED_WIN = 20 clocks).
module tb_pred_governor;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] fc = 0; wire [7:0] cmd; wire safe, aiu, aio; wire [4:0] tr;
    safety_governor #(.PRED_EN(1), .PRED_WIN(20), .PRED_K(2), .PRED_MIN_DELTA(12'd150)) dut (.clk(clk), .rst_n(rst_n), .in_valid(1'b1), .force_code(fc),
        .lut_cmd(8'd100), .adc_invalid(1'b0), .sensor_fault(1'b0), .estop_active(1'b0), .ai_valid(1'b0), .ai_class(2'd0),
        .cmd_out(cmd), .safe_state(safe), .trip_reason(tr), .ai_used(aiu), .ai_overridden(aio));
    reg [15:0] vec [0:5999];
    integer n, i, bad = 0, trips = 0, pass = 0, fail = 0, off_trips = 0;
    task at_cnt(input [31:0] c); begin @(posedge clk); while (dut.wcnt != c) @(posedge clk); end endtask
    initial begin
        $readmemh("tb/pred_vectors.mem", vec);
        n = 0; while (n < 6000 && vec[n] !== 16'hxxxx) n = n + 1;
        repeat (3) @(posedge clk); rst_n = 1;
        at_cnt(3);
        for (i = 0; i < n; i = i + 1) begin
            fc = vec[i][11:0];                 // set at wcnt == 3, snapshot at the end of this window
            at_cnt(2);                         // next window, after the new delta is in
            if (tr[4] !== vec[i][12]) begin bad = bad + 1; if (bad < 4) $display("MISMATCH i=%0d force=%0d expect=%b got=%b", i, vec[i][11:0], vec[i][12], tr[4]); end
            trips = trips + vec[i][12];
            at_cnt(3);
        end
        $display("RESULT pred_rtl_vs_model vectors=%0d expected_trips=%0d mismatches=%0d", n, trips, bad);
        pass = (bad == 0) ? 1 : 0; fail = bad;
        $display("TB tb_pred_governor: PASS %0d FAIL %0d", pass, fail); $finish;
    end
endmodule
