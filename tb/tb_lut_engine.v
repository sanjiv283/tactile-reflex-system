`timescale 1ns / 1ps
// Direct tests of rtl/lut_engine.v (until now it was only exercised through the upload controller).
// Bank convention in the RTL: active_bank=0 reads bank0 and writes go to bank1; swap toggles active_bank.
// Cases marked CHARACTERISATION document what the RTL does today in situations the upload controller never
// creates; they are here so a future change to that behaviour is noticed, not because the behaviour is required.
module tb_lut_engine;
    reg clk = 0;
    always #500 clk = ~clk;                           // 1 MHz

    reg         rst = 1;
    reg  [9:0]  adc_value = 0;
    reg         adc_valid = 0;
    reg         wr_en = 0, swap = 0;
    reg  [5:0]  wr_addr = 0;
    reg  [11:0] wr_data = 0;
    wire [11:0] lut_pulse_us;
    wire        lut_valid, active_bank;

    lut_engine dut (.clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid),
                    .lut_pulse_us(lut_pulse_us), .lut_valid(lut_valid),
                    .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .swap(swap), .active_bank(active_bank));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    task nclk(input integer n); repeat (n) @(negedge clk); endtask

    reg [11:0] oldt [0:63];     // power-up table: 2000 - 16*i
    reg [11:0] newt [0:63];     // test table: 1000 + i (never equal to oldt)
    reg [11:0] res  [0:511];
    integer i, c, S, bad, first_new, nnew, nold, nother;
    reg [5:0] idx6;

    // one lookup, result read one clock later
    reg [11:0] got;
    task look(input [9:0] code);
        begin @(negedge clk); adc_value = code; adc_valid = 1; @(negedge clk); adc_valid = 0; got = lut_pulse_us; end
    endtask
    task write(input [5:0] a, input [11:0] d);
        begin @(negedge clk); wr_addr = a; wr_data = d; wr_en = 1; @(negedge clk); wr_en = 0; end
    endtask
    task do_swap; begin @(negedge clk); swap = 1; @(negedge clk); swap = 0; end endtask
    // all 1024 ADC codes against a table (idx = code>>4): count mismatches
    task sweep(input integer which, output integer mism);   // which: 0 old, 1 new
        integer k;
        begin
            mism = 0;
            for (k = 0; k < 1024; k = k + 1) begin
                look(k[9:0]);
                if (got !== (which == 0 ? oldt[k >> 4] : newt[k >> 4])) mism = mism + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_lut_engine);
        for (i = 0; i < 64; i = i + 1) begin oldt[i] = 2000 - 16 * i; newt[i] = 1000 + i; end
        nclk(4); rst = 0; nclk(2);

        // ---- power-up contents: every ADC code maps to entry code>>4 of the default table
        check(active_bank === 1'b0, "power-up: bank 0 active");
        sweep(0, bad);
        check(bad == 0, "all 1024 ADC codes -> default table entry (code>>4), 2000-16*idx");

        // ---- lookup timing and hold behaviour
        @(negedge clk); adc_value = 10'd320; adc_valid = 1;
        @(negedge clk); adc_valid = 0; adc_value = 10'd0;
        check(lut_valid === 1'b1 && lut_pulse_us === 12'd1680, "lookup: lut_valid and the value arrive one clock after adc_valid");
        @(negedge clk);
        check(lut_valid === 1'b0 && lut_pulse_us === 12'd1680, "lut_valid is a 1-clock pulse; the value is held until the next lookup");

        // ---- writes go to the inactive bank only: the live table must not change while it is being rewritten
        bad = 0;
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk); wr_addr = i[5:0]; wr_data = newt[i]; wr_en = 1;
            adc_value = {i[5:0], 4'b0000}; adc_valid = 1;                 // read the SAME entry in the same clock
            @(negedge clk); wr_en = 0; adc_valid = 0;
            if (lut_pulse_us !== oldt[i]) bad = bad + 1;
        end
        check(bad == 0, "writing 64 entries into the inactive bank never disturbs the live table (read in the same clock)");
        sweep(0, bad);
        check(bad == 0 && active_bank === 1'b0, "after the writes the live table is still entirely the old one");

        // ---- atomic swap under continuous lookups: one transition, exactly at the swap clock
        S = 40;
        for (c = 0; c < 200; c = c + 1) begin
            @(negedge clk);
            idx6 = c % 64; adc_value = {idx6, 4'b0000}; adc_valid = 1; swap = (c == S);
            if (c > 0) res[c-1] = lut_pulse_us;                           // result of the lookup issued one clock earlier
        end
        @(negedge clk); adc_valid = 0; swap = 0; res[199] = lut_pulse_us;
        first_new = -1; nnew = 0; nold = 0; nother = 0;
        for (c = 0; c < 200; c = c + 1) begin
            if (res[c] === newt[c % 64]) begin nnew = nnew + 1; if (first_new < 0) first_new = c; end
            else if (res[c] === oldt[c % 64]) nold = nold + 1;
            else nother = nother + 1;
        end
        check(nother == 0, "during the swap every lookup returns an entry of the old table or of the new table (no mixed or corrupt value)");
        check(first_new == S + 1 && nold == S + 1 && nnew == 200 - (S + 1), "lookups up to and including the swap clock see the old table; the very next one sees the new table");
        bad = 0; for (c = S + 1; c < 200; c = c + 1) if (res[c] !== newt[c % 64]) bad = bad + 1;
        check(bad == 0 && active_bank === 1'b1, "after the swap every lookup is from the new table (single transition, bank 1 active)");
        sweep(1, bad);
        check(bad == 0, "all 1024 ADC codes -> new table entry (code>>4) after the swap");

        // ---- the old table survives in the now-inactive bank; writes now target it, not the live bank
        write(6'd5, 12'd1555);
        look({6'd5, 4'b0000});
        check(got === newt[5], "after the swap a write goes to the other bank: live entry 5 unchanged");
        do_swap;
        look({6'd5, 4'b0000}); check(got === 12'd1555, "second swap: the entry written to the inactive bank is now live");
        look({6'd9, 4'b0000}); check(got === oldt[9], "second swap returns to the old table (all other entries are the old ones)");
        check(active_bank === 1'b0, "two swaps = back to bank 0");

        // ---- reset keeps the tables and the active bank; only lut_valid / lut_pulse_us are cleared
        do_swap;                                                         // bank 1 (new table incl. entry 5 = newt[5]) active again? bank1 = new table
        look({6'd7, 4'b0000}); check(got === newt[7] && active_bank === 1'b1, "bank 1 active before reset");
        @(negedge clk); rst = 1; adc_valid = 1; adc_value = 10'd0;
        @(negedge clk); adc_valid = 0;
        check(lut_valid === 1'b0 && lut_pulse_us === 12'd0, "reset clears lut_valid and lut_pulse_us (a lookup in the reset cycle is dropped)");
        nclk(2); rst = 0; nclk(2);
        check(active_bank === 1'b1, "reset does not change the active bank");
        look({6'd7, 4'b0000}); check(got === newt[7], "reset does not change the table contents");

        // ---- CHARACTERISATION: situations the upload controller never creates
        // (a) write and swap in the same clock: the write lands in the bank that is being swapped IN
        @(negedge clk); wr_addr = 6'd11; wr_data = 12'd1611; wr_en = 1; swap = 1;
        @(negedge clk); wr_en = 0; swap = 0;
        look({6'd11, 4'b0000});
        check(got === 12'd1611 && active_bank === 1'b0, "CHARACTERISATION: write + swap in one clock -> the write is part of the table swapped in");
        // (b) swap while reset is asserted still toggles the bank (the swap is outside the reset branch)
        @(negedge clk); rst = 1; swap = 1;
        @(negedge clk); swap = 0; rst = 0; nclk(2);
        check(active_bank === 1'b1, "CHARACTERISATION: a swap pulse during reset still toggles the active bank");
        // (c) a write during reset is still performed (writes are outside the reset branch)
        @(negedge clk); rst = 1; wr_addr = 6'd20; wr_data = 12'd1620; wr_en = 1;
        @(negedge clk); wr_en = 0; rst = 0; nclk(2);
        do_swap; look({6'd20, 4'b0000});
        check(got === 12'd1620, "CHARACTERISATION: a write issued during reset is still stored in the inactive bank");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #30_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
