`timescale 1ns / 1ps
// Self-checking testbench for the Stage 1 reflex path.
// Sim speed-ups (simulation only): 1 MHz clock (1 clock = 1 us) and a 2.5 ms
// servo frame instead of 20 ms. Pulse widths are unaffected.
// Expected values come from the placeholder LUT: pulse = 2000 - 16*(adc>>4).
module tb_reflex_top;
    localparam CLK_HZ = 1_000_000;
    localparam T      = 1000;            // clock period, ns

    reg clk = 0;
    always #(T/2) clk = ~clk;

    reg        rst_btn = 1, estop_btn = 0, grip_en_sw = 0;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0;
    reg        lut_wr_en = 0, lut_swap = 0;
    reg  [5:0] lut_wr_addr = 0;
    reg [11:0] lut_wr_data = 0;
    wire       servo_out, active_bank_led, dbg_cmd_toggle;
    wire [3:0] fault_led;

    reflex_top #(.CLK_HZ(CLK_HZ), .FRAME_US(2500)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(lut_wr_en), .lut_wr_addr(lut_wr_addr), .lut_wr_data(lut_wr_data),
        .lut_swap(lut_swap),
        .servo_out(servo_out), .fault_led(fault_led),
        .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle)
    );

    // Fake ADC: one sample of adc_in every 50 clocks (stands in for the MCP3008)
    reg [9:0] adc_in   = 0;
    reg       sampling = 1;
    always begin
        repeat (49) @(posedge clk);
        if (sampling) begin adc_value <= adc_in; adc_valid <= 1'b1; end
        @(posedge clk);
        adc_valid <= 1'b0;
    end

    integer errors = 0;

    // Wait for a fresh frame, measure the servo pulse width, compare.
    task check(input integer exp_us, input [3:0] exp_fault, input [8*28-1:0] name);
        realtime t_rise, t_fall;
        integer w;
        begin
            repeat (100) @(posedge clk);          // let a new sample propagate
            @(posedge servo_out); t_rise = $realtime;
            @(negedge servo_out); t_fall = $realtime;
            w = (t_fall - t_rise) / T;
            if (w == exp_us && fault_led == exp_fault)
                $display("PASS  %0s: pulse=%0d us  fault=%b", name, w, fault_led);
            else begin
                $display("FAIL  %0s: pulse=%0d us (exp %0d)  fault=%b (exp %b)",
                         name, w, exp_us, fault_led, exp_fault);
                errors = errors + 1;
            end
        end
    endtask

    task adc_check(input [9:0] v, input integer exp_us, input [3:0] exp_fault,
                   input [8*28-1:0] name);
        begin adc_in = v; check(exp_us, exp_fault, name); end
    endtask

    task do_reset;
        begin
            @(posedge clk) rst_btn <= 1'b1;
            repeat (5) @(posedge clk);
            rst_btn <= 1'b0;
        end
    endtask

    task lut_write(input [5:0] a, input [11:0] d);
        begin
            @(posedge clk); lut_wr_addr <= a; lut_wr_data <= d; lut_wr_en <= 1'b1;
            @(posedge clk); lut_wr_en <= 1'b0;
        end
    endtask

    task lut_swap_now;
        begin
            @(posedge clk); lut_swap <= 1'b1;
            @(posedge clk); lut_swap <= 1'b0;
        end
    endtask

    task check_bank(input b);
        begin
            #1;   // let the swap register update first
            if (active_bank_led !== b) begin
                $display("FAIL  active bank = %b (exp %b)", active_bank_led, b);
                errors = errors + 1;
            end else
                $display("PASS  active bank = %b", b);
        end
    endtask

    realtime t0, t1;
    integer  k, lat, lat_min, lat_max;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(1, tb_reflex_top);

        repeat (10) @(posedge clk);
        rst_btn <= 1'b0;

        // ---- Reset / gripper disabled ----
        check(1000, 4'b0000, "after reset, grip_en=0");
        grip_en_sw <= 1'b1;

        // ---- Normal LUT operation ----
        adc_check(  0, 2000, 4'b0000, "min ADC (no contact)");
        adc_check( 15, 2000, 4'b0000, "LUT boundary adc=15");
        adc_check( 16, 1984, 4'b0000, "LUT boundary adc=16");
        adc_check(320, 1680, 4'b0000, "light contact");
        adc_check(640, 1360, 4'b0000, "normal grip");
        adc_check(880, 1120, 4'b0000, "high force (<FORCE_MAX)");

        // ---- Over-force with hysteresis ----
        adc_check(950, 1000, 4'b0001, "excessive force -> open");
        adc_check(850, 1000, 4'b0001, "hysteresis band, still open");
        adc_check(700, 1312, 4'b0000, "below FORCE_RESUME, resume");

        // ---- FPGA digital-path latency (SIMULATED) ----
        // adc_valid edge -> dbg_cmd_toggle edge, in clock cycles
        adc_in = 300; lat_min = 1000; lat_max = 0;
        for (k = 0; k < 10; k = k + 1) begin
            @(posedge adc_valid);  t0 = $realtime;
            @(dbg_cmd_toggle);     t1 = $realtime;
            lat = (t1 - t0) / T;
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
        end
        $display("INFO  SIMULATED sample->command latency: min=%0d max=%0d clocks, jitter=%0d",
                 lat_min, lat_max, lat_max - lat_min);
        if (lat_min != 2 || lat_max != 2) begin
            $display("FAIL  expected exactly 2 clocks"); errors = errors + 1;
        end

        // ---- Double-buffered LUT update + hard clamp of uploaded values ----
        adc_in = 320;
        lut_write(20, 12'd2500);   // above PULSE_MAX
        lut_write(30, 12'd1500);
        lut_write(40, 12'd500);    // below PULSE_MIN
        check(1680, 4'b0000, "write hits inactive bank only");
        check_bank(1'b0);
        lut_swap_now;
        check_bank(1'b1);
        adc_check(320, 2000, 4'b0000, "new bank, 2500 clamped");
        adc_check(480, 1500, 4'b0000, "new bank entry used");
        adc_check(640, 1000, 4'b0000, "new bank, 500 clamped");
        lut_swap_now;
        check_bank(1'b0);
        adc_check(320, 1680, 4'b0000, "swapped back to bank 0");

        // ---- Sensor range fault (latched) ----
        adc_check(1020, 1000, 4'b0011, "sensor range fault");
        adc_check( 320, 1000, 4'b0010, "range fault stays latched");
        do_reset;
        check(1680, 4'b0000, "reset clears range fault");

        // ---- Emergency stop (latched) + its latency ----
        @(posedge clk); estop_btn <= 1'b1; t0 = $realtime;
        @(dut.pulse_cmd);                  t1 = $realtime;
        $display("INFO  SIMULATED estop->command latency: %0d clocks (2 sync + 1)",
                 $rtoi((t1 - t0) / T));
        repeat (5) @(posedge clk); estop_btn <= 1'b0;
        check(1000, 4'b1000, "e-stop latched after release");
        do_reset;
        check(1680, 4'b0000, "reset clears e-stop");

        // ---- ADC timeout (sensor/ADC stopped responding) ----
        sampling = 0;
        repeat (1500) @(posedge clk);
        check(1000, 4'b0100, "ADC timeout -> safe");
        sampling = 1;
        check(1000, 4'b0100, "timeout stays latched");
        do_reset;
        check(1680, 4'b0000, "reset clears timeout");

        // ---- Gripper disabled ----
        grip_en_sw <= 1'b0;
        check(1000, 4'b0000, "grip_en=0 -> open");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
