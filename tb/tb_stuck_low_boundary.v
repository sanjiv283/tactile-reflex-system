`timescale 1ns / 1ps
// End-to-end frame-boundary test for a MISO line that becomes stuck LOW while the real force is high (880):
// mcp3008_model -> adc_spi_interface -> reflex_top (reflex_top_spi, real 50 MHz clock, 1 MHz SCLK, 1000 us ADC timeout).
// The stuck-low onset is swept across one servo frame (coarse) and, separately, around the offsets where the ADC-timeout
// fault lands on the next frame latch (fine), because fault time = last valid sample + 1000 us.
// For every onset: the ADC-timeout fault must latch; every complete pulse must stay inside 1000..2000 us; at most ONE pulse
// that starts after the fault may still carry the old command (the frame latch is once per frame); every pulse starting
// more than one frame after the fault must be SAFE (1000 us). The clock-exact 40 ns latch window is covered by
// tb_timeout_boundary; this test shows the whole chain.
// FRAME_US_TB = 2500 (fast default) or 20000 (the real servo frame, run_sim.sh --extended); COARSE_US / FINE_US are the sweep steps.
module tb_stuck_low_boundary;
    parameter FRAME_US_TB = 2500;
    parameter COARSE_US   = 625;
    parameter FINE_US     = 20;
    parameter FINE_SPAN   = 80;           // fine sweep covers FRAME-1050 .. FRAME-1050+FINE_SPAN (us after a pulse start)

    reg clk = 0; always #10 clk = ~clk;
    reg rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    wire cs_n, sclk, mosi, adc_dout, servo_out, active_bank_led, dbg_cmd_toggle, frame_err; wire [3:0] fault_led;
    reg stuck = 0;
    wire miso = stuck ? 1'b0 : adc_dout;
    pullup (miso);                                       // the board's MISO pull-up
    reflex_top_spi #(.CLK_HZ(50_000_000), .SCLK_HZ(1_000_000), .FRAME_US(FRAME_US_TB)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led),
        .dbg_cmd_toggle(dbg_cmd_toggle), .adc_frame_err(frame_err));
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    integer errors = 0, runs = 0;
    task check(input cond, input [8*100-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    realtime ps [0:63]; integer pw [0:63]; integer np = 0;
    realtime t_r = 0, t_f = -1, t_on = 0;
    always @(posedge servo_out) t_r = $realtime;
    always @(negedge servo_out) if (np < 64) begin ps[np] = t_r; pw[np] = $rtoi(($realtime - t_r) / 1000.0 + 0.5); np = np + 1; end
    always @(posedge fault_led[2]) if (t_f < 0) t_f = $realtime;

    integer k, old_after, bad_range, late_bad, off, worst_old = 0, bad_runs = 0, nofault_runs = 0;
    realtime lat, worst_lat = 0;
    task run(input integer o);
        begin
            stuck = 0; rst_btn = 1; repeat (6) @(posedge clk); rst_btn = 0;
            #(2 * FRAME_US_TB * 1000.0 + 500_000);                          // healthy for more than two frames
            @(posedge servo_out); #(o * 1000.0); stuck = 1; t_on = $realtime; t_f = -1; np = 0;
            #(1_300_000.0 + 2.2 * FRAME_US_TB * 1000.0); stuck = 0;
            runs = runs + 1; old_after = 0; bad_range = 0; late_bad = 0;
            if (t_f < 0) begin nofault_runs = nofault_runs + 1; $display("FAIL  onset +%0d us: no ADC-timeout fault", o); end
            else begin
                lat = t_f - t_on; if (lat > worst_lat) worst_lat = lat;
                for (k = 0; k < np; k = k + 1) begin
                    if (pw[k] < 1000 || pw[k] > 2000) bad_range = bad_range + 1;
                    if (ps[k] > t_f) begin
                        if (ps[k] < t_f + FRAME_US_TB * 1000.0 + 50_000.0) begin if (pw[k] != 1000) old_after = old_after + 1; end
                        else if (pw[k] != 1000) late_bad = late_bad + 1;
                    end
                end
                if (old_after > worst_old) worst_old = old_after;
                if (bad_range != 0 || old_after > 1 || late_bad != 0) begin
                    bad_runs = bad_runs + 1;
                    $display("FAIL  onset +%0d us: out-of-range pulses=%0d, old-command pulses after fault=%0d, late non-SAFE=%0d", o, bad_range, old_after, late_bad);
                end
            end
        end
    endtask

    initial begin
        u_adc.value[0] = 10'd880;                                           // real force 880 -> 1120 us while the line works
        for (off = 0; off < FRAME_US_TB; off = off + COARSE_US) run(off);
        for (off = FRAME_US_TB - 1050; off <= FRAME_US_TB - 1050 + FINE_SPAN; off = off + FINE_US) run(off);
        $display("INFO  frame=%0d us: %0d onsets, worst stuck-low onset -> ADC-timeout fault %0.1f us, most old-command pulses after the fault: %0d",
                 FRAME_US_TB, runs, worst_lat / 1000.0, worst_old);
        check(nofault_runs == 0, "every stuck-low onset latched the ADC-timeout fault");
        check(bad_runs == 0, "pulses 1000..2000 us, at most one old-command pulse after the fault, SAFE a frame later (all onsets)");
        check(worst_lat <= 1_030_000.0, "stuck-low onset -> ADC-timeout fault within 1000 us timeout + one frame in flight (17.5 us) + margin");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(FRAME_US_TB * 1000.0 * 8 * (FRAME_US_TB / COARSE_US + 12)); $display("FAIL  watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
