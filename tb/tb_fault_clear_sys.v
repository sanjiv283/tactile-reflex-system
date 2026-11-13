`timescale 1ns/1ps
// T-3 fault_clear contract, core level (tactile_reflex_top, CLR_DB=2): reset with the clear button held (e-stop released and
// pressed), e-stop release without a press, and e-stop assertion latency with the clear button held. Covers T2, T6, T9, T10, T11.
module tb_fault_clear_sys;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    reg [11:0] value = 12'h100; reg fc = 0; reg es_n = 1;
    wire cs, sclk, m, pwm, safe, sf, ea, aiv, sv, aio, zr, rsn; wire [11:0] fo; wire [7:0] cmd; wire [4:0] tr;
    ad7476_model adc (.cs_n(cs), .sclk(sclk), .value(value), .corrupt(1'b0), .miso(m));
    tactile_reflex_top #(.PRED_EN(0), .CLR_DB(2)) d (.clk(clk), .rst_n(rst_n), .adc_cs_n(cs), .adc_sclk(sclk), .adc_miso(m), .estop_n(es_n),
        .fault_clear(fc), .ai_gpio(16'd0), .pwm_out(pwm), .safe_state(safe), .sensor_fault(sf), .estop_active(ea), .ai_valid(aiv),
        .dbg_sample_valid(sv), .force_out(fo), .cmd_out(cmd), .trip_reason(tr), .ai_overridden(aio), .zero_run(zr), .rst_sync_n(rsn));
    integer pass = 0, fail = 0, n, h, cyc = 0, t0, lat, lmin, lmax, i, lmin0, lmax0;
    always @(posedge clk) cyc <= cyc + 1;
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task count_pwm(input integer cycles, output integer hi); integer k; begin hi = 0; for (k = 0; k < cycles; k = k + 1) begin @(posedge clk); if (pwm) hi = hi + 1; end end endtask
    task reset_with(input clr, input pin); begin fc = clr; es_n = pin; rst_n = 0; repeat (6) @(posedge clk); rst_n = 1; end endtask
    task fresh_press; begin @(negedge clk); fc = 0; repeat (20) @(negedge clk); fc = 1; repeat (20) @(negedge clk); end endtask
    // e-stop assertion latency, 6 phases; clear is held (hold=1) or released (hold=0) while the e-stop asserts
    task measure(input hold, output integer mn, output integer mx);
        begin
            mn = 1000; mx = 0;
            for (i = 0; i < 6; i = i + 1) begin
                es_n = 1; fresh_press; if (!hold) begin @(negedge clk); fc = 0; repeat (6) @(negedge clk); end
                repeat (6000) @(posedge clk); @(posedge pwm); repeat (i * 211) @(posedge clk);
                @(negedge clk); es_n = 0; t0 = cyc; lat = 0;
                while (pwm !== 1'b0) begin @(negedge clk); lat = cyc - t0; end
                if (lat < mn) mn = lat; if (lat > mx) mx = lat;
                check(ea === 1'b1 && safe === 1'b1, "e-stop latched and safe after assertion");
            end
        end
    endtask
    initial begin
        // ---- T11 / T6: reset while the clear button is held, e-stop pin released ----
        reset_with(1, 1); repeat (40000) @(posedge clk);
        check(ea === 1'b1 && safe === 1'b1, "T11: reset with clear held, e-stop released: e-stop latched and safe after 40000 clocks");
        count_pwm(30000, h); check(h == 0, "T11: PWM never rises while the button stays held (0 high cycles in 30000)");
        fc = 0; repeat (20) @(posedge clk); check(ea === 1'b1 && safe === 1'b1, "T6: releasing the button alone does not clear");
        fc = 1; repeat (20) @(posedge clk); repeat (3000) @(posedge clk);
        check(ea === 1'b0 && safe === 1'b0, "T6: fresh press clears the latch and releases the safe state");
        count_pwm(8192, h); check(h > 0, "T6: PWM runs after the fresh press");
        // ---- T6: reset with the clear held and the e-stop button pressed ----
        reset_with(1, 0); repeat (40000) @(posedge clk);
        check(ea === 1'b1 && safe === 1'b1, "T6: reset with clear held and e-stop pressed: latched and safe");
        es_n = 1; repeat (40000) @(posedge clk);
        check(ea === 1'b1 && safe === 1'b1, "T2/T6: e-stop released while clear still held from before reset: stays latched");
        count_pwm(20000, h); check(h == 0, "T9: e-stop released, clear held, no fresh press: PWM stays low");
        fc = 0; repeat (20) @(posedge clk); fc = 1; repeat (3000) @(posedge clk);
        check(ea === 1'b0 && safe === 1'b0, "T6: release then fresh press clears");
        // ---- T9: e-stop press and release without any clear press ----
        fc = 0; repeat (20) @(posedge clk); count_pwm(8192, h); check(h > 0, "T9: running");
        @(negedge clk); es_n = 0; repeat (20) @(posedge clk); es_n = 1; repeat (2000) @(posedge clk);
        check(ea === 1'b1 && safe === 1'b1, "T9: e-stop released without a clear press: still latched");
        count_pwm(20000, h); check(h == 0, "T9: PWM remains low (0 high cycles in 20000)");
        // ---- T10: e-stop assertion latency with the clear held and released ----
        fresh_press; measure(1, lmin, lmax); $display("RESULT estop_to_pwm_low_cycles clear_held min=%0d max=%0d", lmin, lmax);
        measure(0, lmin0, lmax0); $display("RESULT estop_to_pwm_low_cycles clear_released min=%0d max=%0d", lmin0, lmax0);
        check(lmin == 5 && lmax == 5, "T10: clear held during e-stop assertion: exactly 5 cycles (unchanged, no debounce latency)");
        check(lmin0 == 5 && lmax0 == 5, "T10: baseline with the clear released: 5 cycles");
        $display("TB tb_fault_clear_sys: PASS %0d FAIL %0d", pass, fail); $finish;
    end
    initial begin #400_000_000; $display("TB tb_fault_clear_sys: TIMEOUT"); $finish; end
endmodule
