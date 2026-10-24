`timescale 1ns/1ps
// System testbench: full PL path with a behavioural ADC, scripted AI messages, e-stop and fault injection.
module tb_top;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;                       // 50 MHz
    reg [11:0] value = 12'h000; reg corrupt = 0;
    reg estop_n = 1, fault_clear = 0;
    reg [7:0] hb = 0; reg [8:0] hbc = 0; reg hb_run = 1; reg [1:0] ps_cls = 0; reg ps_valid = 1; reg inv_bad = 0;
    wire [15:0] ai_gpio = {hb, 1'b0, ps_valid, (inv_bad ? ps_cls : ~ps_cls), 2'b00, ps_cls};
    wire cs_n, sclk, miso, pwm, safe, sfault, estop_a, ai_v, dbg_sv, ai_ov; wire [7:0] cmd; wire [4:0] trip;

    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    tactile_reflex_top #(.AI_TIMEOUT(3000), .WD_CYCLES(2000), .PRED_EN(0)) dut (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(miso),
        .estop_n(estop_n), .fault_clear(fault_clear), .ai_gpio(ai_gpio), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sfault),
        .estop_active(estop_a), .ai_valid(ai_v), .dbg_sample_valid(dbg_sv), .cmd_out(cmd), .trip_reason(trip), .ai_overridden(ai_ov));

    reg [7:0] rom [0:255]; initial $readmemh("rtl/force_lut.mem", rom);
    integer cyc = 0; always @(posedge clk) cyc <= cyc + 1;
    always @(posedge clk) if (hb_run) begin hbc <= hbc + 1; if (hbc == 499) begin hbc <= 0; hb <= hb + 1; end end

    integer pass = 0, fail = 0;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task frames(input integer n); integer i; begin for (i = 0; i < n; i = i + 1) begin @(posedge clk); while (!dbg_sv) @(posedge clk); end end endtask
    task settle; begin frames(4); repeat (10) @(posedge clk); end endtask
    task settle_pwm; begin settle; repeat (8192) @(posedge clk); end endtask
    task clear_faults; begin @(negedge clk); fault_clear = 1; repeat (8) @(negedge clk); fault_clear = 0; repeat (4) @(negedge clk); end endtask
    task set_ai(input [1:0] c, input v); begin ps_cls = c; ps_valid = v; end endtask
    function [7:0] lut(input [11:0] code); lut = rom[code >> 4]; endfunction
    task duty_count(output integer h); integer n; begin h = 0; for (n = 0; n < 4096; n = n + 1) begin @(posedge clk); if (pwm) h = h + 1; end end endtask

    // traces for the report figures
    integer fd1, fd2, trace_sel = 0;
    always @(posedge clk) begin
        if (trace_sel == 1) $fdisplay(fd1, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d", cyc, value, dbg_sv, dut.force_code, ps_cls, ai_v, safe, cmd, pwm);
        if (trace_sel == 2) $fdisplay(fd2, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d", cyc, value, estop_n, dut.force_code, ps_cls, ai_v, safe, cmd, pwm);
    end

    integer h, i, off, t0, t_sv, t1, lat_min_in, lat_max_in, lat_min_sv, lat_max_sv, d_in, d_sv, es_lat, es_min, es_max;
    initial begin
        fd1 = $fopen("results/trace_override.csv"); fd2 = $fopen("results/trace_estop.csv");
        $fdisplay(fd1, "cycle,adc_in,sample_valid,force_code,ai_class,ai_valid,safe_state,cmd_out,pwm_out");
        $fdisplay(fd2, "cycle,adc_in,estop_n,force_code,ai_class,ai_valid,safe_state,cmd_out,pwm_out");
        // ---- reset ----
        repeat (6) @(posedge clk); #1 check(pwm === 1'b0 && safe === 1'b1, "in reset: PWM low and safe state");
        rst_n = 1; repeat (4) @(posedge clk); #1 check(safe === 1'b1 && pwm === 1'b0, "after reset: safe until first sample");
        frames(3); repeat (10) @(posedge clk); #1 check(safe === 1'b1 && estop_a === 1'b1, "after reset: held by latched e-stop until operator clear");
        clear_faults; settle; check(safe === 1'b0, "operator clear releases the safe state");
        // ---- no contact ----
        value = 12'h010; set_ai(2'd0, 1); settle_pwm;
        check(safe === 1'b0 && cmd === lut(12'h010) && cmd === 8'd180, "no contact: LUT approach command 180");
        duty_count(h); check(h == 180 * 16, "no contact: PWM high time = 180/256 of the period");
        // ---- light contact ----
        value = 12'h180; set_ai(2'd1, 1); settle; check(safe === 1'b0 && cmd === lut(12'h180), "light contact: command follows LUT");
        // ---- normal grip, AI limits command ----
        value = 12'h400; set_ai(2'd2, 1); settle; check(cmd === 8'd64 && lut(12'h400) > 8'd64, "normal grip: AI class 2 caps the command");
        // ---- AI classification changes ----
        set_ai(2'd0, 1); settle; check(cmd === lut(12'h400), "AI class 0: LUT command");
        set_ai(2'd1, 1); settle; check(cmd === lut(12'h400), "AI class 1: LUT command");
        set_ai(2'd3, 1); settle; check(cmd === 8'd24, "AI class 3: excess cap");
        for (i = 0; i < 4; i = i + 1) begin set_ai(i[1:0], 1); settle; check(cmd <= lut(12'h400), "AI never raises the command above the LUT"); end
        // ---- high force (below limit) ----
        value = 12'h800; set_ai(2'd2, 1); settle; check(safe === 1'b0 && cmd === lut(12'h800), "high force below limit: still running, LUT command low");
        value = 12'h9FF; settle; check(safe === 1'b0, "LUT/limit boundary: 0x9FF is below FORCE_MAX");
        // ---- excessive force with AI claiming normal grip (override) ----
        value = 12'h400; set_ai(2'd2, 1); settle_pwm; @(posedge pwm); trace_sel = 1; repeat (100) @(posedge clk);
        value = 12'hB00; repeat (700) @(posedge clk); trace_sel = 0; settle_pwm;
        check(safe === 1'b1 && cmd === 8'd0 && trip[0] === 1'b1, "excess force: Governor enters safe state");
        check(ai_ov === 1'b1, "excess force: AI 'normal grip' overridden");
        duty_count(h); check(h == 0, "excess force: PWM output stays low");
        value = 12'hA00; settle; check(safe === 1'b1, "boundary: FORCE_MAX exactly trips");
        value = 12'h950; settle; check(safe === 1'b1, "hysteresis holds safe state above FORCE_REL");
        value = 12'h400; settle_pwm;
        check(safe === 1'b0 && cmd === 8'd64, "force back to normal: released and AI limit applies again");
        // ---- AI failure / invalid result ----
        hb_run = 0; repeat (3600) @(posedge clk); frames(1); check(ai_v === 1'b0 && cmd === lut(12'h400), "AI heartbeat lost: FPGA-only command");
        hb_run = 1; repeat (1200) @(posedge clk); settle; check(ai_v === 1'b1 && cmd === 8'd64, "AI heartbeat back: AI limit applies");
        inv_bad = 1; settle; check(ai_v === 1'b0 && cmd === lut(12'h400), "AI integrity check fails: AI ignored");
        inv_bad = 0; set_ai(2'd2, 0); settle; check(ai_v === 1'b0 && cmd === lut(12'h400), "PS marks result invalid: AI ignored");
        value = 12'hB00; set_ai(2'd2, 0); settle; check(safe === 1'b1, "AI invalid and excess force: safe state regardless");
        value = 12'h400; set_ai(2'd2, 1); settle;
        // ---- sensor failure ----
        corrupt = 1; settle; check(safe === 1'b1 && trip[3] === 1'b1, "ADC frame error: invalid ADC trips safe state");
        frames(3); check(sfault === 1'b1, "persistent invalid ADC latches sensor fault");
        corrupt = 0; settle; check(safe === 1'b1, "fault stays latched after the ADC recovers");
        clear_faults; settle; check(safe === 1'b0 && sfault === 1'b0, "operator clear releases sensor fault");
        value = 12'hFFF; settle; check(safe === 1'b1 && trip[3] === 1'b1, "railed ADC value (0xFFF): safe state");
        value = 12'h400; frames(2); clear_faults; settle; check(safe === 1'b0, "recovers after railed value removed and fault cleared");
        force dut.force_valid = 1'b0; repeat (2300) @(posedge clk); #1 check(sfault === 1'b1 && safe === 1'b1, "ADC watchdog: no samples -> sensor fault");
        release dut.force_valid; frames(3); clear_faults; settle; check(safe === 1'b0, "recovers after samples resume");
        set_ai(2'd0, 1);
        // ---- emergency stop (functional) ----
        value = 12'h010; settle_pwm; @(posedge pwm);
        @(negedge clk); estop_n = 0; repeat (6) @(negedge clk); check(pwm === 1'b0 && safe === 1'b1 && trip[2] === 1'b1, "e-stop: PWM low and safe state");
        estop_n = 1; settle_pwm; check(safe === 1'b1, "e-stop latched after release");
        clear_faults; settle_pwm; check(safe === 1'b0 && cmd === 8'd180, "operator clear restores operation");
        // ---- e-stop latency measurement (clock cycles) ----
        es_min = 1000; es_max = 0;
        for (i = 0; i < 6; i = i + 1) begin
            @(posedge pwm); repeat (i * 211) @(posedge clk); if (i == 0) trace_sel = 2;
            @(negedge clk); estop_n = 0; t0 = cyc; es_lat = 0;
            while (pwm !== 1'b0) begin @(negedge clk); es_lat = cyc - t0; end
            if (es_lat < es_min) es_min = es_lat; if (es_lat > es_max) es_max = es_lat;
            repeat (20) @(posedge clk); estop_n = 1; repeat (40) @(posedge clk); trace_sel = 0; clear_faults; settle_pwm;
        end
        $display("RESULT estop_to_pwm_low_cycles min=%0d max=%0d jitter=%0d", es_min, es_max, es_max - es_min);
        check(es_max <= 6, "e-stop to PWM low within 6 clock cycles");
        // ---- force path latency measurement ----
        set_ai(2'd0, 1); lat_min_in = 100000; lat_max_in = 0; lat_min_sv = 100000; lat_max_sv = 0;
        for (i = 0; i < 12; i = i + 1) begin
            value = 12'h100; settle_pwm; @(posedge pwm); repeat (i * 113) @(posedge clk);
            @(negedge clk); value = 12'hB00; t0 = cyc; t_sv = -1; t1 = -1;
            while (t1 < 0) begin @(negedge clk);
                if (t_sv < 0 && dbg_sv && dut.sample == 12'hB00) t_sv = cyc;
                if (t_sv >= 0 && pwm === 1'b0) t1 = cyc; end
            d_in = t1 - t0; d_sv = t1 - t_sv;
            if (d_in < lat_min_in) lat_min_in = d_in; if (d_in > lat_max_in) lat_max_in = d_in;
            if (d_sv < lat_min_sv) lat_min_sv = d_sv; if (d_sv > lat_max_sv) lat_max_sv = d_sv;
        end
        $display("RESULT adc_input_change_to_pwm_low_cycles min=%0d max=%0d jitter=%0d", lat_min_in, lat_max_in, lat_max_in - lat_min_in);
        $display("RESULT sample_valid_to_pwm_low_cycles min=%0d max=%0d jitter=%0d", lat_min_sv, lat_max_sv, lat_max_sv - lat_min_sv);
        check(lat_max_sv - lat_min_sv == 0 && lat_max_sv == 4, "logic path: sample_valid to PWM low is 4 cycles, zero jitter");
        // ---- reset during operation ----
        value = 12'h100; settle_pwm; @(posedge pwm); rst_n = 0; repeat (3) @(posedge clk); #1 check(pwm === 1'b0 && safe === 1'b1, "reset mid-operation: PWM low, safe state");
        rst_n = 1; repeat (4) @(posedge clk); frames(3); #1 check(safe === 1'b1 && sfault === 1'b0, "after reset: safe until operator clear, faults cleared");
        clear_faults; settle; check(safe === 1'b0, "operation resumes after clear");
        $display("TB tb_top: PASS %0d FAIL %0d", pass, fail); $fclose(fd1); $fclose(fd2); $finish;
    end
    initial begin #60_000_000; $display("TB tb_top: TIMEOUT"); $finish; end
endmodule
