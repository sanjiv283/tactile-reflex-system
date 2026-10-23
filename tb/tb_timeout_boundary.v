`timescale 1ns / 1ps
// Clock-exact test of the ADC-timeout fault against the servo frame latch (reflex_top at the real 50 MHz clock).
// The ADC-timeout path (also taken by a stuck-low MISO, whose frames are rejected) is: safety_governor f_timeout rises at clock
// edge E; pulse_us becomes SAFE one edge later (E+1); servo_pwm_generator samples pulse_us at the frame latch edge B.
// Prediction: the latch takes the OLD command when B <= E+1 (fault set no earlier than one clock before the latch edge,
// a 2-clock = 40 ns window at 50 MHz) and SAFE (1000 us) when B >= E+2; the following latch is always SAFE.
// The latch under test is the 2nd one (the first that carries a real command). E is placed at B+d for d = -SPAN..+SPAN by stopping the injected ADC samples at the right clock (E = last_sample + constant).
// FRAME_US_TB = 2500 (default, fast) or 20000 (the real servo frame, run_sim.sh --extended).
module tb_timeout_boundary;
    parameter FRAME_US_TB = 2500;
    parameter SPAN        = 4;
    reg clk = 0; always #10 clk = ~clk;

    reg rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    reg [9:0] adc_value = 10'd640;                      // placeholder LUT: 2000 - 16*40 = 1360 us
    reg adc_valid = 0;
    wire servo_out, active_bank_led, dbg_cmd_toggle; wire [3:0] fault_led;
    reflex_top #(.CLK_HZ(50_000_000), .FRAME_US(FRAME_US_TB)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle));

    integer errors = 0;
    task check(input cond, input [8*100-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    integer cyc = 0, relbase = 0, last_L = 0, nl = 0, Erel = -1;
    integer Brel [0:7];
    integer Vl   [0:7];
    reg inject_en = 0, f_prev = 0, latch_prev = 0;
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (latch_prev) Vl[nl-1] = dut.u_pwm.pulse_latched;              // value taken at the previous edge
        latch_prev = 0;
        if (dut.u_pwm.us_tick && dut.u_pwm.us_cnt == FRAME_US_TB - 1 && !dut.u_pwm.rst && nl < 8) begin
            Brel[nl] = cyc - relbase; nl = nl + 1; latch_prev = 1;
        end
        if (dut.u_gov.f_timeout && !f_prev && Erel < 0) Erel = cyc - 1 - relbase;
        f_prev = dut.u_gov.f_timeout;
        adc_valid <= inject_en && ((cyc - relbase) <= last_L) && (((cyc - relbase) % 50) == 0 || (cyc - relbase) == last_L);
    end

    task run(input integer L);                                            // L: relative clock of the last injected sample
        begin
            inject_en = 0; rst_btn = 1; repeat (6) @(posedge clk);
            nl = 0; Erel = -1; latch_prev = 0; f_prev = 0;
            @(posedge clk); rst_btn = 0; relbase = cyc; last_L = L; inject_en = 1;
            while (nl < 3) @(posedge clk);
            repeat (3) @(posedge clk);
        end
    endtask

    integer Bcal, Kcal, d, first_old, exp_old, nwin_old;
    initial begin
        run(1 << 28);                                                     // calibration 1: healthy, no fault
        check(Erel < 0 && Vl[1] == 1360 && fault_led == 4'b0000, "calibration: healthy samples, no timeout, LUT command 1360 us latched");
        Bcal = Brel[1];                                                   // 2nd latch: the first one that carries a real command
        run(Bcal - 20000);                                                // calibration 2: samples stop well before the 3rd latch
        Kcal = Erel - (Bcal - 20000);
        $display("INFO  frame=%0d us: 2nd latch edge B=%0d, f_timeout edge E = last sample + %0d clocks (timeout 50000 clocks)", FRAME_US_TB, Bcal, Kcal);
        first_old = 99999; nwin_old = 0;
        for (d = -SPAN; d <= SPAN; d = d + 1) begin
            run(Bcal + d - Kcal);
            exp_old = (d >= -1);
            if (Erel - Brel[1] != d) begin $display("FAIL  stimulus: wanted E-B=%0d, got %0d", d, Erel - Brel[1]); errors = errors + 1; end
            else if (Vl[1] == (exp_old ? 1360 : 1000) && Vl[2] == 1000 && fault_led[2])
                $display("PASS  E-B=%0d clocks (%0d ns): latch under test = %0d us (%0s), next latch SAFE", d, d*20, Vl[1], exp_old ? "old command" : "SAFE");
            else begin
                $display("FAIL  E-B=%0d: latches %0d %0d (expected %0d then 1000), fault=%b", d, Vl[1], Vl[2], exp_old ? 1360 : 1000, fault_led);
                errors = errors + 1;
            end
            if (Vl[1] == 1360 && d < first_old) first_old = d;
            if (Vl[1] == 1360) nwin_old = nwin_old + 1;
        end
        $display("INFO  old command latched for E-B >= %0d clocks only; window of old-command outcomes seen: %0d of %0d offsets", first_old, nwin_old, 2*SPAN+1);
        check(first_old == -1, "boundary: SAFE is latched when the fault is set 2 or more clocks (40 ns) before the latch edge");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(FRAME_US_TB * 1000.0 * 4 * (2*SPAN + 4)); $display("FAIL  watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
