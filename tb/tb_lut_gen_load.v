`timescale 1ns / 1ps
// Generated-LUT loading test: rtl/lut_engine.v with INIT_FILE = a file written by python/lut_gen.py.
// run_sim.sh creates both files in a temporary directory and passes their paths with -P:
//   FILE   hex file written by lut_gen.py (one 3-digit hex word per line) -> lut_engine INIT_FILE
//   EXPECT decimal file written from python lut_gen.make_lut(): the expected pulse of every entry
//   NEXP   how many leading entries FILE really holds (64 normally; fewer/0 = the "incomplete file" characterisation)
// Every entry is read back through the engine's normal lookup (adc code -> lut_pulse_us), for the bank that is
// active at power-up and, after one swap, for the second bank (both are loaded by the same $readmemh).
module tb_lut_gen_load;
    parameter FILE   = "";
    parameter EXPECT = "";
    parameter NEXP   = 64;

    reg clk = 0;
    always #500 clk = ~clk;                           // 1 MHz

    reg         rst = 1, adc_valid = 0, swap = 0;
    reg  [9:0]  adc_value = 0;
    wire [11:0] lut_pulse_us;
    wire        lut_valid, active_bank;

    lut_engine #(.INIT_FILE(FILE)) dut (.clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_pulse_us(lut_pulse_us), .lut_valid(lut_valid),
        .wr_en(1'b0), .wr_addr(6'd0), .wr_data(12'd0), .swap(swap), .active_bank(active_bank));

    integer errors = 0;
    task check(input cond, input [8*112-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    integer expv [0:63];
    integer fd, n, r, i, k, bad, bad_x, ncmp, nunk, nd, mn, mx;
    reg [11:0] got;

    // one lookup: set the code, let the engine register it, read the result one clock later
    task lookup(input [9:0] code);
        begin
            @(negedge clk); adc_value = code; adc_valid = 1;
            @(negedge clk); adc_valid = 0;
            got = lut_pulse_us;
        end
    endtask

    // all 64 entries x three ADC codes inside each entry's range (first, middle, last code)
    task sweep(input integer first_bad_report);
        begin
            bad = 0; bad_x = 0; ncmp = 0; nunk = 0;     // ncmp: lookups compared with a Python value; nunk: lookups of entries the file lacks
            for (i = 0; i < 64; i = i + 1)
                for (k = 0; k < 3; k = k + 1) begin
                    lookup(16 * i + ((k == 0) ? 0 : (k == 1) ? 7 : 15));
                    if (i < NEXP) begin
                        ncmp = ncmp + 1;
                        if (!(lut_valid === 1'b1 && got === expv[i][11:0])) begin
                            bad = bad + 1;
                            if (bad <= first_bad_report) $display("      entry %0d: got %0d (%h), expected %0d", i, got, got, expv[i]);
                        end
                    end else begin
                        nunk = nunk + 1;
                        if (got !== 12'hxxx) bad_x = bad_x + 1;   // an entry the file does not hold that is NOT x
                    end
                end
        end
    endtask

    initial begin #50_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end

    initial begin
        // expected values, from the Python side
        fd = $fopen(EXPECT, "r");
        check(fd != 0, "expected-value file opened");
        n = 0;
        if (fd != 0) begin
            r = 1;
            while (r == 1 && n < 64) begin
                r = $fscanf(fd, "%d\n", expv[n]);
                if (r == 1) n = n + 1;
            end
            $fclose(fd);
        end
        check(n == 64, "expected-value file holds exactly 64 entries");
        mn = 99999; mx = 0; nd = 0;
        for (i = 0; i < n; i = i + 1) begin
            if (expv[i] < mn) mn = expv[i];
            if (expv[i] > mx) mx = expv[i];
            if (i > 0 && expv[i] != expv[i-1]) nd = nd + 1;
        end
        $display("INFO  expected table: first=%0d last=%0d min=%0d max=%0d, %0d value changes; FILE=%0s NEXP=%0d",
                 expv[0], expv[63], mn, mx, nd, FILE, NEXP);
        check(nd >= 10 && mn < mx, "fixture varies across the table (not constant)");

        repeat (3) @(negedge clk); rst = 0; repeat (2) @(negedge clk);
        check(active_bank === 1'b0, "power-up: bank 0 active");

        sweep(5);
        // Prove how many lookups were really compared: 3 per entry the file holds, so 192 for a full file.
        if (NEXP == 64) check(bad == 0 && ncmp == 192, "bank 0: all 64 entries equal the Python values (192 lookups compared)");
        else if (NEXP > 0) check(bad == 0 && ncmp == 3 * NEXP, "bank 0: the entries present in the file equal the Python values (3 lookups each, all compared)");
        else check(ncmp == 0, "bank 0: file holds no entries: no Python value is compared (0 comparisons, not a pass)");
        if (NEXP < 64) check(bad_x == 0 && nunk == 3 * (64 - NEXP), "bank 0: every entry the file does not hold reads as unknown (x), all looked up");
        if (NEXP > 0) begin
            lookup(10'd0);    check(got === expv[0][11:0],   "boundary: ADC 0 -> entry 0");
            if (NEXP == 64) begin
                lookup(10'd1023); check(got === expv[63][11:0], "boundary: ADC 1023 -> entry 63");
            end
        end

        @(negedge clk); swap = 1; @(negedge clk); swap = 0; @(negedge clk);
        check(active_bank === 1'b1, "swap: bank 1 active");
        sweep(5);
        // Prove how many lookups were really compared: 3 per entry the file holds, so 192 for a full file.
        if (NEXP == 64) check(bad == 0 && ncmp == 192, "bank 1: all 64 entries equal the Python values (192 lookups compared)");
        else if (NEXP > 0) check(bad == 0 && ncmp == 3 * NEXP, "bank 1: the entries present in the file equal the Python values (3 lookups each, all compared)");
        else check(ncmp == 0, "bank 1: file holds no entries: no Python value is compared (0 comparisons, not a pass)");
        if (NEXP < 64) check(bad_x == 0 && nunk == 3 * (64 - NEXP), "bank 1: every entry the file does not hold reads as unknown (x), all looked up");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
endmodule
