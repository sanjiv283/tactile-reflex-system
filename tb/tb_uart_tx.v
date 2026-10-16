`timescale 1ns / 1ps
// Self-checking testbench for uart_tx. Defaults: 100 MHz clock, 115200 baud (placeholders).
// Other settings: -Ptb_uart_tx.CLK_HZ=27000000   -Ptb_uart_tx.BAUD=1000000
// The line is decoded by tb/uart_monitor.v (independent of the DUT) and by the real uart_rx.
module tb_uart_tx;
    parameter CLK_HZ = 100_000_000;
    parameter BAUD   = 115200;
    localparam integer CPB = (CLK_HZ + BAUD/2) / BAUD;     // clocks per bit the DUT must use
    localparam real    T   = 1.0e9 / CLK_HZ;
    localparam real    BIT = CPB * T;                      // exact bit time

    // The clock generator rounds its half period to 1 ps, so long intervals drift by a fraction of a
    // clock; time checks therefore allow +-half a clock (a one-clock error would still be caught).
    localparam real TOL = T / 2.0;

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg        rst = 1, tx_valid = 0;
    reg  [7:0] tx_data = 0;
    wire       tx_ready, tx, busy;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx(tx), .busy(busy));

    // independent decoder + the real receiver
    wire [7:0] mdata; wire mvalid; wire [31:0] mn, mfe;
    uart_monitor #(.BIT_NS(BIT)) mon (.rx(tx), .data(mdata), .valid(mvalid), .n_bytes(mn), .n_fe(mfe));
    wire [7:0] rdata; wire rvalid, rfe, rbusy;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) rx_i (
        .clk(clk), .rst(rst), .rx(tx), .data(rdata), .valid(rvalid), .frame_err(rfe), .busy(rbusy));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    reg [7:0] mq [0:255]; integer nm = 0;
    reg [7:0] rq [0:255]; integer nr = 0, nrfe = 0;
    always @(posedge mvalid) begin mq[nm % 256] = mdata; nm = nm + 1; end
    always @(posedge clk) begin
        if (rvalid) begin rq[nr % 256] = rdata; nr = nr + 1; end
        if (rfe) nrfe = nrfe + 1;
    end

    // edge log: every transition of tx
    real t_fall [0:63]; real t_rise [0:63]; integer nf = 0, nrs = 0;
    always @(negedge tx) begin t_fall[nf % 64] = $realtime; nf = nf + 1; end
    always @(posedge tx) begin t_rise[nrs % 64] = $realtime; nrs = nrs + 1; end

    // present a byte and wait until it is accepted (tx_valid is left high for back-to-back use)
    task put(input [7:0] b);
        begin
            tx_data = b; tx_valid = 1'b1;
            @(posedge clk); while (!tx_ready) @(posedge clk);
            #1;
        end
    endtask
    task put_end; begin tx_valid = 1'b0; end endtask
    task wait_idle; begin while (busy) @(posedge clk); repeat (3 * CPB) @(posedge clk); end endtask

    integer i, n0, nr0, k0, ready_clks;
    reg ok;
    reg [7:0] pat [0:11];
    real d;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart_tx);
        $display("INFO  CLK_HZ=%0d BAUD=%0d -> %0d clocks/bit (actual %0.1f baud)", CLK_HZ, BAUD, CPB, 1.0e9 / BIT);

        // ---- 1. reset state
        repeat (5) @(posedge clk); #1;
        check(tx === 1'b1 && busy === 1'b0 && tx_ready === 1'b1, "reset: line idle high, not busy, ready");
        rst = 0; repeat (3 * CPB) @(posedge clk);
        check(nf == 0 && nm == 0, "idle line: no edges, no bytes");

        // ---- 2. single bytes, awkward values, decoded by the independent monitor and by uart_rx
        pat[0] = 8'h00; pat[1] = 8'hFF; pat[2] = 8'h55; pat[3] = 8'hAA; pat[4] = 8'hA5; pat[5] = 8'h5A;
        pat[6] = 8'h01; pat[7] = 8'h80; pat[8] = 8'h7F; pat[9] = 8'h3C; pat[10] = 8'hC3; pat[11] = 8'h06;
        n0 = nm; nr0 = nr; ok = 1;
        for (i = 0; i < 12; i = i + 1) begin
            put(pat[i]); put_end; wait_idle;
            if (nm != n0 + i + 1 || mq[(n0 + i) % 256] !== pat[i]) ok = 0;
        end
        check(ok, "12 bytes (00 FF 55 AA A5 5A 01 80 7F 3C C3 06) decoded in order by the monitor");
        ok = 1;
        for (i = 0; i < 12; i = i + 1) if (rq[(nr0 + i) % 256] !== pat[i]) ok = 0;
        check(ok && nr == nr0 + 12 && nrfe == 0, "same 12 bytes received by uart_rx, no framing error");
        check(mfe == 0, "monitor saw no framing error (stop bit always high)");

        // ---- 3. exact bit timing: 0x00 = start + 8 zero bits low for 9 bits, 0xFF = start only low for 1 bit
        k0 = nf;
        put(8'h00); put_end; wait_idle;
        d = t_rise[(nrs - 1) % 64] - t_fall[k0 % 64];
        check(d > 9 * BIT - TOL && d < 9 * BIT + TOL, "0x00: line low for exactly 9 bit times (start + 8 data)");
        k0 = nf; n0 = nrs;
        put(8'hFF); put_end; wait_idle;
        d = t_rise[n0 % 64] - t_fall[k0 % 64];
        check(d > BIT - TOL && d < BIT + TOL, "0xFF: start bit is exactly 1 bit time");

        // ---- 4. back-to-back bytes: continuous stream, exactly 10 bit times per byte, no gap
        n0 = nm; k0 = nf;
        for (i = 0; i < 6; i = i + 1) put(8'h00);
        put_end; wait_idle;
        ok = 1;
        for (i = 1; i < 6; i = i + 1) begin
            d = t_fall[(k0 + i) % 64] - t_fall[(k0 + i - 1) % 64];
            if (!(d > 10 * BIT - TOL && d < 10 * BIT + TOL)) ok = 0;
        end
        check(ok && nf == k0 + 6, "6 back-to-back 0x00 bytes: start edges exactly 10 bit times apart (no gap)");
        n0 = nm; nr0 = nr;
        for (i = 0; i < 12; i = i + 1) put(pat[i]);
        put_end; wait_idle;
        ok = 1;
        for (i = 0; i < 12; i = i + 1) if (mq[(n0 + i) % 256] !== pat[i] || rq[(nr0 + i) % 256] !== pat[i]) ok = 0;
        check(ok && nm == n0 + 12 && nr == nr0 + 12, "12 back-to-back mixed bytes decoded correctly by monitor and uart_rx");
        check(mfe == 0 && nrfe == 0, "no framing errors in back-to-back streams");

        // ---- 5. handshake: ready only when it can accept, one clock at the end of the stop bit
        tx_data = 8'h55; tx_valid = 1;
        @(posedge clk); while (!tx_ready) @(posedge clk); #1; tx_valid = 0;
        ready_clks = 0;
        repeat (10 * CPB - 2) begin @(posedge clk); #1; if (tx_ready) ready_clks = ready_clks + 1; end
        check(ready_clks == 0 && busy === 1'b1, "busy and not ready while a byte is on the wire");
        ready_clks = 0;
        repeat (8) begin @(posedge clk); #1; if (tx_ready) ready_clks = ready_clks + 1; end
        check(ready_clks >= 1, "ready again at the end of the stop bit / idle");
        wait_idle;
        check(tx_ready === 1'b1 && busy === 1'b0 && tx === 1'b1, "idle again: ready, not busy, line high");

        // ---- 6. reset during transmission: line high at once, stays idle, then recovers
        n0 = nm; k0 = nf;
        put(8'h00); put_end;
        repeat (CPB * 3 + CPB / 2) @(posedge clk);          // inside data bit 2
        check(tx === 1'b0 && busy === 1'b1, "mid-byte: line low, busy (before reset)");
        @(posedge clk); #1 rst = 1; @(posedge clk); #1;
        check(tx === 1'b1 && busy === 1'b0 && tx_ready === 1'b1, "reset mid-byte: line idle high on the next clock");
        repeat (3) @(posedge clk); #1 rst = 0;
        k0 = nf; repeat (30 * CPB) @(posedge clk);
        check(nf == k0 && tx === 1'b1, "after reset: no edges for 30 bit times (nothing resumes)");
        n0 = nm; nr0 = nr;
        put(8'hA5); put_end; wait_idle;
        check(nm >= n0 + 1 && mq[(nm - 1) % 256] === 8'hA5, "first byte after the reset is received intact by the monitor");
        check(nr > nr0 && rq[(nr - 1) % 256] === 8'hA5, "... and by uart_rx");

        // ---- 7. reset while back-to-back streaming: queue is just a producer holding tx_valid
        n0 = nm;
        put(8'hC3); put(8'h3C);                              // second byte now on the wire
        repeat (CPB * 4) @(posedge clk);
        @(posedge clk); #1 rst = 1; tx_valid = 0; repeat (2) @(posedge clk); #1 rst = 0;
        check(tx === 1'b1 && busy === 1'b0, "reset during a back-to-back stream: idle high");
        repeat (12 * CPB) @(posedge clk);                    // let the monitor finish the cut-off byte
        put(8'h42); put_end; wait_idle;
        check(mq[(nm - 1) % 256] === 8'h42, "stream resumes cleanly with the next byte after the reset");

        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(BIT * 6000 + 1_000_000); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
