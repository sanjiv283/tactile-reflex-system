`timescale 1ns/1ps
// Experiment testbench (separate from the existing regression): replays a per-step stimulus file through the
// real tactile_reflex_top and logs the outputs at the end of each step. One step = 25000 clk = 500 us at 50 MHz.
// Stimulus word: [11:0] ADC code, [12] sample present, [13] frame error, [14] estop_n, [15] fault_clear.
// Run from the repository root (LUT path). AI input is tied off, so the AI path is invalid and ignored.
module tb_experiments;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 0; reg corrupt = 0, estop_n = 1, fault_clear = 0;
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [4:0] trip; wire [11:0] fo;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    tactile_reflex_top dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso), .estop_n(estop_n),
        .fault_clear(fault_clear), .ai_gpio(16'd0), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a),
        .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .force_out(fo), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));
    reg [15:0] stim [0:4095]; reg [8*256-1:0] fn; reg [8*64-1:0] id;
    integer cyc = 0, nsteps, i, t0, lat, c; reg safe0;
    always @(posedge clk) cyc <= cyc + 1;
    task apply(input [15:0] w); begin
        value = w[11:0]; corrupt = w[13]; estop_n = w[14]; fault_clear = w[15];
        if (w[12]) release dut.force_valid; else force dut.force_valid = 1'b0;
    end endtask
    initial begin
        for (i = 0; i < 4096; i = i + 1) stim[i] = 16'hxxxx;
        if (!$value$plusargs("STIM=%s", fn) || !$value$plusargs("ID=%s", id)) begin $display("ERROR missing +STIM/+ID"); $finish; end
        $readmemh(fn, stim);
        nsteps = 0; while (stim[nsteps] !== 16'hxxxx) nsteps = nsteps + 1;
        apply(stim[0]); repeat (6) @(posedge clk); rst_n = 1;
        for (i = 0; i < nsteps; i = i + 1) begin
            @(negedge clk); apply(stim[i]); t0 = cyc; lat = -1; safe0 = safe;
            for (c = 0; c < 25000; c = c + 1) begin @(posedge clk); if (lat < 0 && safe && !safe0) lat = cyc - t0; end
            $display("RTL,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d", id, i, safe, cmd, trip, sfault, estop_a, lat);
        end
        $finish;
    end
endmodule
