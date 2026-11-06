`timescale 1ns/1ps
// Frame-granular validation (NEW; does not replace tb_experiments.v). Run from the repository root.
// MODE 0: one stimulus word per ADC frame (word k latched by the ADC model at the k-th CS fall), outputs logged ~4.5 clk after each sample_valid.
// MODE 1: dropout - force force_valid low at several phases after a sample_valid and measure clocks until sensor_fault.
// MODE 2: count sample_valid pulses (ADC frames) in 25000-clk windows.
// Word: [11:0] code, [13] frame error, [14] estop_n, [15] fault_clear. AI input tied off.
module tb_frames;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'd400; reg corrupt = 0, estop_n = 1, fault_clear = 0;
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [4:0] trip; wire [11:0] fo;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    tactile_reflex_top dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso), .estop_n(estop_n),
        .fault_clear(fault_clear), .ai_gpio(16'd0), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a),
        .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .force_out(fo), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));
    reg [15:0] stim [0:4095]; reg [8*256-1:0] fn; reg [8*64-1:0] id; integer mode, n, k, i, j, cyc = 0, t0, w, cnt;
    integer offs [0:3]; reg done;
    always @(posedge clk) cyc <= cyc + 1;
    task apply(input [15:0] x); begin value = x[11:0]; corrupt = x[13]; estop_n = x[14]; fault_clear = x[15]; end endtask
    task wait_sv; begin @(posedge clk); while (!dbg_sv) @(posedge clk); end endtask
    initial begin
        if (!$value$plusargs("MODE=%d", mode)) mode = 0;
        if (!$value$plusargs("ID=%s", id)) id = "x";
        if (mode == 0) begin
            for (i = 0; i < 4096; i = i + 1) stim[i] = 16'hxxxx;
            if (!$value$plusargs("STIM=%s", fn)) begin $display("ERROR no +STIM"); $finish; end
            $readmemh(fn, stim); n = 0; while (stim[n] !== 16'hxxxx) n = n + 1;
            apply(stim[0]); repeat (6) @(posedge clk); rst_n = 1;
            for (k = 0; k < n; k = k + 1) begin
                wait_sv; repeat (4) @(negedge clk);
                $display("FRM,%0s,%0d,%0d,%0d,%0d,%0d,%0d", id, k, safe, cmd, trip, sfault, estop_a);
                @(negedge clk); if (k + 1 < n) apply(stim[k + 1]);
            end
        end else if (mode == 1) begin
            offs[0] = 0; offs[1] = 17; offs[2] = 53; offs[3] = 91;
            repeat (6) @(posedge clk); rst_n = 1; repeat (300) @(posedge clk);
            @(negedge clk); fault_clear = 1; repeat (8) @(negedge clk); fault_clear = 0; repeat (500) @(posedge clk);
            for (j = 0; j < 4; j = j + 1) begin
                wait_sv; repeat (offs[j]) @(posedge clk); @(negedge clk);
                force dut.force_valid = 1'b0; t0 = cyc; done = 0;
                while (!sfault && (cyc - t0) < 5000) @(negedge clk);
                $display("DRP,phase_after_sample_valid=%0d,clocks_force_to_sensor_fault=%0d,safe=%0d,trip=%0d", offs[j], cyc - t0, safe, trip);
                release dut.force_valid; repeat (600) @(posedge clk);
                @(negedge clk); fault_clear = 1; repeat (8) @(negedge clk); fault_clear = 0; repeat (500) @(posedge clk);
            end
        end else begin
            repeat (6) @(posedge clk); rst_n = 1; repeat (500) @(posedge clk);
            for (j = 0; j < 4; j = j + 1) begin cnt = 0; for (i = 0; i < 25000; i = i + 1) begin @(posedge clk); if (dbg_sv) cnt = cnt + 1; end
                $display("CNT,window=%0d,sample_valid_pulses_per_25000_clk=%0d", j, cnt); end
        end
        $finish;
    end
endmodule
