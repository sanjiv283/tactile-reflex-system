`timescale 1ns/1ps
// Exactly ONE corrupted ADC frame through the real RTL (tb_experiments cannot do this: its step is ~240 frames).
// Documented rule under test: one invalid sample trips safe_state (trip bit 3) but is below INVALID_LIMIT, so no latched sensor fault.
module tb_single_invalid;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'd400; reg corrupt = 0, estop_n = 1, fault_clear = 0;
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [4:0] trip; wire [11:0] fo;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    tactile_reflex_top dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso), .estop_n(estop_n),
        .fault_clear(fault_clear), .ai_gpio(16'd0), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault), .estop_active(estop_a),
        .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .force_out(fo), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));
    integer c, t_on = -1, t_off = -1, cyc = 0; reg safe_seen = 0, sf_ever = 0; reg [4:0] trip_or = 0; reg safe_prev;
    always @(posedge clk) cyc <= cyc + 1;
    initial begin
        repeat (6) @(posedge clk); rst_n = 1; repeat (2000) @(posedge clk);
        @(negedge clk); fault_clear = 1; repeat (2000) @(posedge clk); @(negedge clk); fault_clear = 0; repeat (5000) @(posedge clk);
        if (safe) $display("ERROR not in normal state before injection");
        @(posedge cs_n); @(negedge clk); corrupt = 1; @(negedge cs_n); #1 corrupt = 0;   // frame latched with corrupt bit, next frame clean
        safe_prev = safe;
        for (c = 0; c < 2000; c = c + 1) begin
            @(posedge clk);
            if (safe && !safe_prev && t_on < 0) t_on = cyc;
            if (!safe && safe_prev && t_off < 0) t_off = cyc;
            safe_prev = safe;
            if (safe) safe_seen = 1; trip_or = trip_or | trip; if (sfault) sf_ever = 1;
        end
        $display("RTLX,single_invalid_frame,safe_seen=%0d,trip_bits_or=%0d,sensor_fault_ever=%0d,final_safe=%0d,final_cmd=%0d,safe_on_to_off_cycles=%0d",
                 safe_seen, trip_or, sf_ever, safe, cmd, (t_on >= 0 && t_off >= 0) ? t_off - t_on : -1);
        $finish;
    end
endmodule
