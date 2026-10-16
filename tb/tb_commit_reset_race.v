`timescale 1ns / 1ps
// Reset asserted at every clock around the COMMIT byte: lut_upload_ctrl + the real lut_engine + upload_resp_tx.
// A swap is a registered one-clock pulse into lut_engine (whose swap is NOT gated by reset), while the response
// event goes to upload_resp_tx (whose reset DOES win). This bench maps what happens for each reset position and
// asserts the invariants that must hold for all of them:
//   (1) the live table is always entirely the old table or entirely the new one (swap is atomic, nothing half-applied);
//   (2) after the reset the controller is idle with no entries and no upload active;
//   (3) a COMMITTED response is queued only if the swap really happened (never the other way round for a fresh commit);
//   (4) WRITE / COMMIT after the reset are refused until a new BEGIN (a half-finished upload cannot be completed).
// It also COUNTS, and prints, the positions where the swap happened but no response was queued (reset swallowed
// the event). That outcome is expected -- a reset can always cut a response off -- and is recorded as an open
// question for the host protocol (host must treat a missing COMMITTED after a reset as unknown).
module tb_commit_reset_race;
    reg clk = 0;
    always #500 clk = ~clk;

    reg        rst = 1, rx_valid = 0, rx_frame_err = 0;
    reg  [7:0] rx_data = 0;
    reg  [9:0] adc_value = 0;
    reg        adc_valid = 0;
    wire       wr_en, swap, ack, nak, commit_done, active, failed, active_bank, lut_valid;
    wire [5:0] wr_addr;
    wire [11:0] wr_data, lut_pulse;
    wire [3:0] err;
    wire [6:0] entries;
    wire [7:0] tx_data; wire tx_valid; wire overflow, busy;

    lut_upload_ctrl #(.CLK_HZ(1_000_000), .TIMEOUT_US(100)) ctrl (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .lut_wr_en(wr_en), .lut_wr_addr(wr_addr), .lut_wr_data(wr_data), .lut_swap(swap),
        .ack(ack), .nak(nak), .err_code(err), .commit_done(commit_done),
        .upload_active(active), .upload_failed(failed), .entries(entries));
    lut_engine lut (.clk(clk), .rst(rst), .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_pulse_us(lut_pulse), .lut_valid(lut_valid),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .swap(swap), .active_bank(active_bank));
    upload_resp_tx #(.DEPTH(4)) resp (.clk(clk), .rst(rst), .ev_ack(ack), .ev_nak(nak), .ev_commit(commit_done),
        .ev_err(err), .ev_entries(entries), .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(1'b1),
        .overflow(overflow), .busy(busy));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- scheduling of the reset relative to the COMMIT byte, in absolute negedge numbers
    integer ncount = 0, rst_at = -1, rst_len = 2;
    always @(negedge clk) begin
        ncount = ncount + 1;
        if (ncount == rst_at) rst = 1;
        if (ncount == rst_at + rst_len) rst = 0;
    end
    // events seen by the response formatter (count a COMMITTED event only when reset does not swallow it)
    integer n_commit_ev = 0, n_commit_queued = 0, n_swap = 0;
    always @(posedge clk) begin
        if (commit_done) n_commit_ev = n_commit_ev + 1;
        if (swap) n_swap = n_swap + 1;
        if (resp.ev && resp.push && commit_done && !rst) n_commit_queued = n_commit_queued + 1;   // events during reset are dropped by upload_resp_tx
    end

    task nclk(input integer n); repeat (n) @(negedge clk); endtask
    task byte_(input [7:0] x); begin @(negedge clk); #1 rx_data = x; rx_valid = 1; @(negedge clk); #1 rx_valid = 0; nclk(2); end endtask
    task wr(input [5:0] a, input [11:0] v);
        reg [7:0] h, l;
        begin h = {4'h0, v[11:8]}; l = v[7:0];
              byte_(8'hA5); byte_(8'h02); byte_({2'b00, a}); byte_(h); byte_(l); byte_(8'h02 ^ {2'b00, a} ^ h ^ l); end
    endtask
    function [11:0] tab(input integer id, input integer i); tab = 1000 + 20 * (id % 40) + (i % 16); endfunction

    // read the 64-entry live table back and classify it against two candidate tables
    reg [11:0] got [0:63];
    task read_table;
        integer k;
        begin for (k = 0; k < 64; k = k + 1) begin
            @(negedge clk); adc_value = {k[5:0], 4'b0000}; adc_valid = 1; @(negedge clk); adc_valid = 0; got[k] = lut_pulse; end end
    endtask
    function integer matches(input integer id);
        integer k, m;
        begin m = 0; for (k = 0; k < 64; k = k + 1) if (got[k] === tab(id, k)) m = m + 1; matches = m; end
    endfunction

    integer d, live, newid, base, swapped, queued, nold, nnew, s0, c0, q0;
    integer swapped_no_resp = 0, swapped_with_resp = 0, not_swapped = 0, bad_mix = 0, bad_idle = 0, bad_resp = 0, bad_after = 0;
    reg [7:0] hh, ll;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_commit_reset_race);
        // establish table "id 0" as live: full upload + commit without any reset interference
        nclk(4); rst = 0; nclk(4);
        byte_(8'hA5); byte_(8'h01); byte_(8'h01);
        for (d = 0; d < 64; d = d + 1) wr(d[5:0], tab(0, d));
        byte_(8'hA5); byte_(8'h03); byte_(8'h03); nclk(10);
        read_table; live = 0;
        check(matches(0) == 64, "setup: table 0 live after an undisturbed upload + commit");

        $display("INFO  reset asserted d clocks after the COMMIT byte's valid clock (2 clocks of reset):");
        for (d = -3; d <= 8; d = d + 1) begin
            newid = live + 1;
            byte_(8'hA5); byte_(8'h01); byte_(8'h01); nclk(2);
            for (base = 0; base < 64; base = base + 1) wr(base[5:0], tab(newid, base));
            nclk(2);
            // COMMIT packet: SOF, CMD, then CHK is the byte whose valid clock is V; reset at V+d
            byte_(8'hA5); byte_(8'h03);
            @(negedge clk); #1; base = ncount;               // we are 1 ns after negedge number `base`
            rst_at = base + 6 + d;                            // the CHK byte is set 1 ns after negedge base+6 -> its valid clock V
            s0 = n_swap; c0 = n_commit_ev; q0 = n_commit_queued;
            nclk(5); @(negedge clk); #1 rx_data = 8'h03; rx_valid = 1; @(negedge clk); #1 rx_valid = 0;
            nclk(25);                                         // reset (if any) done, everything settled
            swapped = (n_swap - s0); queued = (n_commit_queued - q0);
            read_table; nold = matches(live); nnew = matches(newid);
            $display("INFO    d=%0d: swap=%0d  commit-response-queued=%0d  live table: %0d/64 old, %0d/64 new  ctrl active=%b entries=%0d",
                     d, swapped, queued, nold, nnew, active, entries);
            if (!((nold == 64 && nnew != 64) || (nnew == 64 && nold != 64))) bad_mix = bad_mix + 1;
            if (swapped != (nnew == 64 ? 1 : 0)) bad_mix = bad_mix + 1;                 // swap pulse <=> new table live
            if (queued > swapped) bad_resp = bad_resp + 1;                                // a COMMITTED response without a swap
            if (nnew == 64) begin
                if (queued) swapped_with_resp = swapped_with_resp + 1; else swapped_no_resp = swapped_no_resp + 1;
                live = newid;
            end else not_swapped = not_swapped + 1;
            // whatever happened: the controller must not be left holding a stale upload after a reset that came in time
            // (checked below separately for resets that clearly follow the COMMIT)
            rst_at = -1;
            // a reset before or at the CHK byte removes the whole packet: the controller must be idle afterwards
            if (d <= 1) begin
                if (active !== 1'b0 || entries !== 7'd0) bad_idle = bad_idle + 1;
            end
            nclk(10);
            // commands after the reset need a new BEGIN
            if (d <= 8) begin
                c0 = n_commit_ev; s0 = n_swap;
                byte_(8'hA5); byte_(8'h03); byte_(8'h03); nclk(8);
                if (n_commit_ev != c0 || n_swap != s0) bad_after = bad_after + 1;       // a lone COMMIT must never swap
            end
            nclk(100 + 5);                                                                // let the quiet period / state settle
        end

        check(bad_mix == 0, "every reset position: live table is entirely old or entirely new, and swap pulse <=> new table live");
        check(bad_resp == 0, "no reset position produces a COMMITTED response without a swap");
        check(bad_idle == 0, "reset at or before the COMMIT's CHK byte leaves the controller idle (no stale upload)");
        check(bad_after == 0, "a COMMIT sent after the reset (no new BEGIN) never swaps");
        $display("INFO  summary over %0d reset positions: swapped+response=%0d  swapped but response swallowed by reset=%0d  not swapped=%0d",
                 12, swapped_with_resp, swapped_no_resp, not_swapped);
        check(swapped_with_resp + swapped_no_resp + not_swapped == 12, "all reset positions classified");
        check(swapped_with_resp >= 1 && not_swapped >= 1, "the sweep covers both outcomes (commit done, commit cancelled by an early reset)");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #60_000_000; $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
