`timescale 1ns / 1ps
// Stage 2 integration: mcp3008_model -> adc_spi_interface -> reflex_top (via reflex_top_spi).
// Real 100 MHz clock, 1 MHz SCLK and the real 1000 us ADC timeout.
// Default run shortcut: 2.5 ms servo frame instead of 20 ms (pulse widths unaffected).
// Extended run (run_sim.sh --extended) overrides FRAME_US=20000 for the real 20 ms frame.
// Expected values come from the placeholder LUT: pulse = 2000 - 16*(adc>>4); safe/open = 1000 us.
module tb_reflex_top_spi;
    parameter FRAME_US    = 2500;
    parameter WATCHDOG_NS = 300_000_000;
    localparam real T         = 10.0;
    localparam      HALF      = 50;
    localparam      CONV_CLKS = 35*HALF + 1;      // 1751

    reg clk = 0;
    always #(T/2) clk = ~clk;

    reg  rst_btn = 1, estop_btn = 0, grip_en_sw = 0;
    wire cs_n, sclk, mosi, adc_dout, servo_out, active_bank_led, dbg_cmd_toggle, frame_err;
    wire [3:0] fault_led;

    reg  adc_connected = 1;                        // 0 = MISO wire open (pull-up reads 1)
    reg  miso_stuck_low = 0;                       // 1 = MISO shorted to ground
    wire miso;
    assign miso = miso_stuck_low ? 1'b0 : (adc_connected ? adc_dout : 1'bz);
    pullup (miso);                                 // FPGA pin pull-up (to be enabled in constraints)

    reflex_top_spi #(.CLK_HZ(100_000_000), .SCLK_HZ(1_000_000), .FRAME_US(FRAME_US)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led),
        .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle),
        .adc_frame_err(frame_err)
    );
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task ticks(input integer n); repeat (n) @(posedge clk); endtask
    task do_reset; begin @(posedge clk) rst_btn <= 1'b1; ticks(5); rst_btn <= 1'b0; end endtask

    // channel-0 force; let two conversions through so the new value reaches the governor
    task setf(input [9:0] v); begin u_adc.value[0] = v; ticks(2*CONV_CLKS + 20); end endtask

    // servo pulse width in us: skip one pulse (may predate the command), measure the next
    function integer us_of(input realtime a, input realtime b); us_of = (b - a) / 1000.0; endfunction
    realtime t_r, t_f;
    integer  w;
    task pulse_w;
        begin
            @(posedge servo_out); @(negedge servo_out);
            @(posedge servo_out); t_r = $realtime; @(negedge servo_out); t_f = $realtime;
            w = us_of(t_r, t_f);
        end
    endtask
    task check_pulse(input [9:0] v, input integer exp, input [8*40-1:0] name);
        begin
            setf(v); pulse_w;
            if (w == exp && fault_led == 4'b0000) $display("PASS  %0s: adc=%0d -> pulse=%0d us", name, v, w);
            else begin $display("FAIL  %0s: adc=%0d pulse=%0d us (exp %0d) fault=%b", name, v, w, exp, fault_led);
                       errors = errors + 1; end
        end
    endtask

    // observation
    realtime cs_fall [0:15];
    integer  nfall = 0, nrise = 0;
    reg [7:0] chmask = 0;
    realtime t_csr, t_tog;
    always @(negedge cs_n) begin cs_fall[nfall % 16] = $realtime; nfall = nfall + 1; end
    always @(posedge cs_n) begin t_csr = $realtime; nrise = nrise + 1; chmask = chmask | (8'd1 << u_adc.last_channel); end
    always @(dbg_cmd_toggle) t_tog = $realtime;

    // pulse counters, sampled every clock so a 1-clock pulse is counted exactly once
    integer nerr = 0, nvalid = 0;
    always @(posedge clk) begin
        if (frame_err)      nerr   = nerr + 1;
        if (dut.data_valid) nvalid = nvalid + 1;
    end

    // bounded wait for the ADC-timeout fault (fault_led[2]); sets to_expired instead of hanging
    reg to_expired;
    task wait_timeout_fault(input integer maxclk);
        integer k;
        begin
            k = 0; to_expired = 0;
            while (!fault_led[2] && k < maxclk) begin @(posedge clk); k = k + 1; end
            if (!fault_led[2]) to_expired = 1;
        end
    endtask

    // command monitor: any clock with the command different from SAFE while watch_pc is set
    reg watch_pc = 0; integer pc_bad = 0;
    always @(posedge clk) if (watch_pc && dut.u_core.pulse_cmd !== 12'd1000) pc_bad = pc_bad + 1;

    integer i, n0, lat, lat_min, lat_max, ok_i, e0, v0, f0, c0;
    realtime t_valid, t_fault, per;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_reflex_top_spi);
        for (i = 0; i < 8; i = i + 1) u_adc.value[i] = 10'd999;   // wrong channels are loud
        u_adc.value[0] = 10'd0;

        // ---- 1. Reset: no SPI activity, no servo pulses, gripper open
        ticks(40);
        check(cs_n === 1 && sclk === 0 && mosi === 0 && nfall == 0, "reset: SPI idle (CS high, SCLK/MOSI low)");
        check(servo_out === 0 && fault_led === 4'b0000, "reset: no servo pulse, no fault");
        rst_btn <= 1'b0; grip_en_sw <= 1'b1;

        // ---- 2. Force readings through SPI -> LUT -> servo pulse
        check_pulse(  0, 2000, "no contact");
        check_pulse(320, 1680, "light contact");
        check_pulse(640, 1360, "normal grip");
        check_pulse(880, 1120, "high force (<FORCE_MAX)");
        check(chmask == 8'h01 && u_adc.diff_requests == 0, "only channel 0 read, single-ended");

        // ---- 3. Sample period seen on CS
        ok_i = 1;
        for (i = nfall - 5; i < nfall; i = i + 1) begin
            per = (cs_fall[i % 16] - cs_fall[(i - 1) % 16]) / T;
            if (per < CONV_CLKS - 0.01 || per > CONV_CLKS + 0.01) ok_i = 0;
        end
        check(ok_i, "CS-to-CS period = 1751 clocks (17.51 us)");

        // ---- 4. Over-force with hysteresis
        setf(950); check(fault_led == 4'b0001 && dut.u_core.pulse_cmd == 1000, "950: over-force -> open");
        setf(850); check(fault_led == 4'b0001 && dut.u_core.pulse_cmd == 1000, "850: hysteresis, still open");
        setf(700); check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1312, "700: resume");

        // ---- 5. Latency CS rise -> dbg_cmd_toggle (SIMULATED; excludes FPGA I/O delays)
        lat_min = 1000; lat_max = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge cs_n); ticks(6);
            lat = (t_tog - t_csr) / T;
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
        end
        $display("INFO  SIMULATED CS rise -> dbg_cmd_toggle: min=%0d max=%0d clocks, jitter=%0d",
                 lat_min, lat_max, lat_max - lat_min);
        check(lat_min == 2 && lat_max == 2, "latency exactly 2 clocks");

        // ---- 6. Healthy run: no timeout, enough samples
        n0 = nrise; ticks(500_000);                      // 5 ms
        $display("INFO  %0d conversions in 5 ms", nrise - n0);
        check((nrise - n0) >= 280 && fault_led == 4'b0000, "5 ms healthy: >=280 samples, no fault");

        // ---- 7. MISO disconnected: frame_err frames keep running, timeout still trips
        // frame_err frames arrive every ~17.5 us. If they restarted the governor's timer the
        // fault would never fire, so "fault raised ~1000 us after the last VALID sample" while
        // >=50 frame_err frames arrived in between proves frame_err does not feed the timer.
        setf(300); check(dut.u_core.pulse_cmd == 1712, "300 -> 1712 us before disconnect");
        @(posedge cs_n); t_valid = $realtime;            // last valid sample (data_valid on this edge)
        ticks(2); e0 = nerr; v0 = nvalid; adc_connected = 0;
        wait_timeout_fault(150_000);                     // budget 1500 us
        t_fault = $realtime;
        check(!to_expired, "ADC timeout fault raised within 1500 us of disconnect");
        $display("INFO  ADC timeout fired %0.2f us after the last valid sample; %0d frame_err frames in between",
                 (t_fault - t_valid) / 1000.0, nerr - e0);
        check((t_fault - t_valid) > 999_000 && (t_fault - t_valid) < 1_002_000, "timeout ~1000 us after last VALID sample");
        check(nerr - e0 >= 50, "frame_err frames kept arriving during the timer window");
        check(nvalid == v0, "no data_valid after disconnect");
        ticks(5);
        check(dut.u_core.pulse_cmd == 1000 && fault_led == 4'b0100, "timeout -> gripper open, fault bit 2");
        e0 = nerr; f0 = nfall; v0 = nvalid; ticks(6*CONV_CLKS);
        check(nfall - f0 >= 4 && nerr - e0 >= 4 && nvalid == v0,
              "after fault: SPI keeps polling, every frame is frame_err, no valid data");
        @(posedge cs_n); ticks(2); adc_connected = 1; ticks(4*CONV_CLKS);
        check(nvalid > v0 && fault_led == 4'b0100 && dut.u_core.pulse_cmd == 1000, "reconnected: samples valid again, timeout stays latched");
        do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1712, "reset recovers (300 -> 1712 us)");

        // ---- 8. Reset in the middle of a conversion
        @(negedge cs_n); c0 = u_adc.conversions; v0 = nvalid;   // counters taken at the start of THIS frame
        ticks(20*HALF);                                  // about SCLK rising edge 10
        check(cs_n === 1'b0, "reset armed: conversion in progress (CS low)");
        @(posedge clk) rst_btn <= 1'b1; ticks(6);        // 2-clock reset synchronizer + margin
        check(cs_n === 1'b1 && sclk === 1'b0 && mosi === 1'b0, "mid-frame reset: CS released, SCLK/MOSI low");
        check(u_adc.conversions == c0 && nvalid == v0, "mid-frame reset: aborted frame produced no data");
        rst_btn <= 1'b0; ticks(3*CONV_CLKS);
        check(nvalid > v0 && u_adc.conversions > c0 && fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1712,
              "after mid-frame reset: sampling resumes, no fault, 300 -> 1712 us");

        // ---- 9. MISO stuck LOW: detected (stuck-low check in rtl/adc_spi_interface.v; it used to be undetectable)
        // The MCP3008 output is high-impedance until the null bit, so the pull-up must read 1 at SCLK rising edge 5.
        // A line shorted to ground reads 0 there: the frame is rejected (frame_err), no data_valid reaches the governor,
        // its 1000 us ADC timeout latches and the pulse is SAFE. Real force stays 880 in the model throughout.
        // (Datasheet and electrical assumptions behind this are NOT confirmed - see README.)
        u_adc.value[0] = 10'd880; ticks(2*CONV_CLKS + 20);
        check(dut.u_core.pulse_cmd == 1120 && fault_led == 4'b0000, "stuck-low baseline: real force 880 -> 1120 us");
        @(posedge cs_n); ticks(2); miso_stuck_low = 1;
        e0 = nerr; v0 = nvalid; ticks(300_000);          // 3 ms = 3x the ADC timeout
        $display("INFO  stuck-low MISO: %0d valid frames, %0d frame_err, fault_led=%b, pulse=%0d us (model still holds 880)",
                 nvalid - v0, nerr - e0, fault_led, dut.u_core.pulse_cmd);
        check(nerr - e0 >= 150 && nvalid - v0 <= 1, "stuck-low: frames rejected as frame_err (at most the frame in flight)");
        check(fault_led == 4'b0100 && dut.u_core.pulse_cmd == 1000,
              "stuck-low: ADC timeout latched, SAFE 1000 us (not read as zero force)");
        @(posedge cs_n); ticks(2); miso_stuck_low = 0; ticks(3*CONV_CLKS);
        check(nvalid > v0 && fault_led == 4'b0100 && dut.u_core.pulse_cmd == 1000,
              "stuck-low released: samples valid again, fault stays latched");
        do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1120, "stuck-low: reset recovers (880 -> 1120 us)");

        // ---- 9b. Legitimate steady readings are NOT stuck-low (code 0 = zero force must be accepted)
        v0 = nvalid; e0 = nerr; u_adc.value[0] = 10'd0; ticks(500_000);              // 5 ms of steady code 0
        check(fault_led == 4'b0000 && nerr == e0 && nvalid - v0 > 200 && dut.u_core.pulse_cmd == 2000,
              "steady legitimate code 0: valid frames, no fault, LUT[0] = 2000 us");
        v0 = nvalid; e0 = nerr; u_adc.value[0] = 10'd300; ticks(500_000);
        check(fault_led == 4'b0000 && nerr == e0 && nvalid - v0 > 200 && dut.u_core.pulse_cmd == 1712,
              "steady code 300: valid frames, no fault");

        // ---- 9c. Short stuck-low glitch (< 1 ms ADC timeout) is tolerated, a longer one latches
        @(posedge cs_n); ticks(2); miso_stuck_low = 1; ticks(60_000);                   // 600 us
        @(posedge cs_n); ticks(2); miso_stuck_low = 0; ticks(5*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1712, "600 us stuck-low glitch: no fault, operation continues");
        @(posedge cs_n); ticks(2); miso_stuck_low = 1; ticks(120_000);                  // 1200 us
        @(posedge cs_n); ticks(2); miso_stuck_low = 0; ticks(5*CONV_CLKS);
        check(fault_led == 4'b0100 && dut.u_core.pulse_cmd == 1000, "1200 us stuck-low: ADC timeout latched, SAFE");
        do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1712, "glitch test: reset recovers");

        // ---- 9d. Stuck low from power-up: the command never leaves SAFE
        miso_stuck_low = 1; do_reset; ticks(4); pc_bad = 0; watch_pc = 1; ticks(300_000);
        watch_pc = 0;
        check(fault_led == 4'b0100 && pc_bad == 0, "power-up with stuck-low MISO: command stays SAFE (1000 us), ADC timeout latched");
        miso_stuck_low = 0; do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1712, "power-up stuck-low: reset recovers");

        // ---- 10. Range fault through the SPI path (latched)
        setf(1020); check(fault_led == 4'b0011 && dut.u_core.pulse_cmd == 1000, "1020: range fault + over-force");
        setf(100);  check(fault_led == 4'b0010 && dut.u_core.pulse_cmd == 1000, "range fault latched");
        do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1904, "reset clears range fault (100 -> 1904 us)");

        // ---- 11. E-stop through the full path (latched)
        @(posedge clk) estop_btn <= 1'b1; ticks(6); estop_btn <= 1'b0; ticks(4);
        check(fault_led == 4'b1000 && dut.u_core.pulse_cmd == 1000, "e-stop -> open, latched after release");
        ticks(3*CONV_CLKS); check(fault_led == 4'b1000, "e-stop stays latched");
        do_reset; ticks(4*CONV_CLKS);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1904, "reset clears e-stop");

        // ---- 12. Grip disabled (not a fault)
        grip_en_sw <= 1'b0; ticks(10);
        check(fault_led == 4'b0000 && dut.u_core.pulse_cmd == 1000, "grip_en=0 -> open, no fault");

        // ---- 13. Datasheet timing over the whole run
        check(u_adc.violations == 0, "MCP3008 timing: zero violations over entire run");
        check(chmask == 8'h01, "no channel other than 0 ever requested");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end

    initial begin #(WATCHDOG_NS); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
