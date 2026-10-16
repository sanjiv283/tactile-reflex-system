`timescale 1ns / 1ps
// How fast does a safety fault reach the SERVO PULSE? (reflex_top = LUT + governor + servo_pwm_generator)
// servo_pwm_generator latches the command once per frame, so after a fault the pulse that is already running keeps
// its old width, and the next pulse is SAFE unless the fault arrived within a few clocks before the frame boundary.
// Sweep: a fault is applied at many offsets inside a frame (e-stop, over-force sample, grip disable), and the widths
// of the pulses that START after the fault are measured in clocks.
//   Required (asserted):  the SECOND pulse after a fault is always SAFE (1000 us); at most one pulse after the
//                         fault still carries the old command.
//   Measured (printed):   the latest offset (clocks before the frame boundary) at which an e-stop still reaches the
//                         very next pulse.
// 1 MHz clock, 2.5 ms servo frame (2500 clocks), ADC samples injected every 50 clocks.
module tb_fault_latency;
    localparam FRAME_CLKS = 2500;
    reg clk = 0;
    always #500 clk = ~clk;

    reg        rst_btn = 1, estop_btn = 0, grip_en_sw = 1;
    reg  [9:0] adc_value = 0, force_val = 10'd640;
    reg        adc_valid = 0;
    wire       servo_out, active_bank_led, dbg_cmd_toggle;
    wire [3:0] fault_led;
    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2500)) dut (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(servo_out), .fault_led(fault_led), .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // ADC sample every 50 clocks carrying force_val
    integer fc = 0;
    always @(negedge clk) begin fc = fc + 1; adc_valid <= (fc % 50 == 0); adc_value <= force_val; end

    // pulse monitor in clocks
    integer cyc = 0, hi = 0, nrise = 0, nwid = 0;
    integer rise_cyc [0:1023];
    integer wid_clk  [0:1023];
    reg prev = 0, cur = 0;
    always @(posedge clk) begin
        cur = servo_out;
        if (cur === 1'b1 && prev === 1'b0) begin rise_cyc[nrise % 1024] = cyc; nrise = nrise + 1; hi = 0; end
        if (cur === 1'b1) hi = hi + 1;
        if (cur === 1'b0 && prev === 1'b1) begin wid_clk[nwid % 1024] = hi; nwid = nwid + 1; end
        prev = cur;
        cyc = cyc + 1;
    end
    task nclk(input integer n); repeat (n) @(posedge clk); endtask
    task wait_rise_after(input integer k); begin while (nrise <= k) @(posedge clk); end endtask

    // restore a healthy, steady state: reset, force 640, grip on, three full frames
    task restore;
        begin
            force_val = 10'd640; grip_en_sw = 1;
            @(posedge clk); rst_btn = 1; nclk(6); rst_btn = 0;
            nclk(2 * FRAME_CLKS + 600);
        end
    endtask

    // one trial: src 0 = e-stop, 1 = over-force, 2 = grip disable; off = clocks after a frame start
    integer r0, tf, j, w1, w2, k;
    task trial(input integer src, input integer off);
        begin
            restore;
            k = nrise; wait_rise_after(k);                      // a frame has just started
            nclk(off);
            tf = cyc;
            case (src)
                0: begin estop_btn = 1; nclk(6); estop_btn = 0; end
                1: force_val = 10'd950;
                default: grip_en_sw = 0;
            endcase
            // index of the first pulse that starts after the fault (walk back from the newest rise)
            j = nrise; while (j > 0 && rise_cyc[(j - 1) % 1024] > tf) j = j - 1;
            while (nrise < j + 2) @(posedge clk);                // wait until the second of those pulses has started
            while (nwid < j + 2) @(posedge clk);                 // ... and ended, so both widths are recorded
            w1 = wid_clk[j % 1024]; w2 = wid_clk[(j + 1) % 1024];
        end
    endtask

    integer src, off, bad_second, old_first, trials, min_old_off, win_max;
    reg [8*8-1:0] sname;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fault_latency);
        nclk(20); rst_btn = 0;
        restore;
        check(wid_clk[(nwid - 1) % 1024] == 1360, "steady state: force 640 -> 1360 clocks (= 1360 us)");

        for (src = 0; src < 3; src = src + 1) begin
            bad_second = 0; old_first = 0; trials = 0; min_old_off = FRAME_CLKS;
            // over-force arrives through an ADC sample (one every 50 clocks), so its window is wider by up to one sample period
            win_max = 24 + ((src == 1) ? 50 : 0);
            for (off = 0; off < FRAME_CLKS; off = off + 167) begin                    // coarse sweep over the whole frame
                trial(src, off); trials = trials + 1;
                if (w2 != 1000) bad_second = bad_second + 1;
                if (w1 != 1000 && w1 != 1360) bad_second = bad_second + 1;           // anything else would be a corrupt width
                if (w1 != 1000) begin old_first = old_first + 1; if (off < min_old_off) min_old_off = off; end
            end
            for (off = FRAME_CLKS - win_max - 6; off < FRAME_CLKS; off = off + ((src == 1) ? 3 : 1)) begin   // fine sweep to the boundary
                trial(src, off); trials = trials + 1;
                if (w2 != 1000) bad_second = bad_second + 1;
                if (w1 != 1000 && w1 != 1360) bad_second = bad_second + 1;
                if (w1 != 1000) begin old_first = old_first + 1; if (off < min_old_off) min_old_off = off; end
            end
            case (src) 0: sname = "e-stop"; 1: sname = "overforc"; default: sname = "grip off"; endcase
            if (old_first == 0) $display("INFO  %0s: %0d trials; the fault reached the very next pulse every time", sname, trials);
            else $display("INFO  %0s: %0d trials; the next pulse was still old in %0d of them, all within the last %0d clocks before the frame boundary",
                          sname, trials, old_first, FRAME_CLKS - min_old_off);
            check(bad_second == 0, "the second pulse after the fault is always SAFE (1000 us) and widths are never corrupt");
            check(old_first == 0 || (FRAME_CLKS - min_old_off) <= win_max, "a fault reaches the very next pulse unless it comes in the last few clocks before a frame boundary");
        end

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #4_000_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
