`timescale 1ns / 1ps
// Self-checking testbench for uart_rx. Defaults: 100 MHz clock, 115200 baud (placeholders).
// Other settings: iverilog -Ptb_uart_rx.CLK_HZ=27000000 ... or -Ptb_uart_rx.BAUD=1000000 ...
module tb_uart_rx;
    parameter CLK_HZ = 100_000_000;
    parameter BAUD   = 115200;
    localparam real T      = 1.0e9 / CLK_HZ;
    localparam real BIT_NS = 1.0e9 / BAUD;

    reg clk = 0;
    always #(T/2.0) clk = ~clk;

    reg  rst = 1, rx = 1;
    wire [7:0] data;
    wire valid, frame_err, busy;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .rx(rx), .data(data), .valid(valid), .frame_err(frame_err), .busy(busy));

    integer errors = 0;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask

    // monitor: log every valid byte, count frame errors, detect wide valid pulses
    reg [7:0] got [0:255];
    integer nrx = 0, nfe = 0, wide = 0;
    reg pv = 0;
    always @(posedge clk) begin
        if (valid) begin got[nrx % 256] = data; nrx = nrx + 1; end
        if (frame_err) nfe = nfe + 1;
        if (valid && pv) wide = wide + 1;
        pv <= valid;
    end

    // bit time scaled by 'scale' to model a sender whose baud differs from the receiver's
    task send_bits(input [7:0] d, input real scale, input stop_level);
        integer i;
        begin
            rx = 1'b0; #(BIT_NS * scale);
            for (i = 0; i < 8; i = i + 1) begin rx = d[i]; #(BIT_NS * scale); end
            rx = stop_level; #(BIT_NS * scale);
        end
    endtask
    task send(input [7:0] d); begin send_bits(d, 1.0, 1'b1); end endtask
    task idle_bits(input integer n); begin rx = 1'b1; #(BIT_NS * n); end endtask

    integer i, n0, f0;
    reg ok;
    reg [7:0] pat [0:9];

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart_rx);
        $display("INFO  CLK_HZ=%0d BAUD=%0d -> %0d clocks/bit", CLK_HZ, BAUD, (CLK_HZ + BAUD/2) / BAUD);

        // ---- 1. reset state
        #(T * 10);
        check(busy === 1'b0 && valid === 1'b0 && frame_err === 1'b0 && data === 8'h00, "reset: idle, no outputs");
        rst = 0; idle_bits(2);
        check(nrx == 0 && nfe == 0, "no activity on an idle line");

        // ---- 2. single frames, awkward values
        pat[0] = 8'h00; pat[1] = 8'hFF; pat[2] = 8'h55; pat[3] = 8'hAA; pat[4] = 8'hA5;
        pat[5] = 8'h01; pat[6] = 8'h80; pat[7] = 8'h7F; pat[8] = 8'h3C; pat[9] = 8'hC3;
        n0 = nrx; ok = 1;
        for (i = 0; i < 10; i = i + 1) begin
            send(pat[i]); idle_bits(1);
            if (nrx != n0 + i + 1 || got[(n0 + i) % 256] !== pat[i]) ok = 0;
        end
        check(ok, "10 frames (00 FF 55 AA A5 01 80 7F 3C C3) received in order");
        check(nfe == 0 && wide == 0, "no frame_err, valid always 1 clock wide");

        // ---- 3. back-to-back frames (stop bit directly followed by next start bit)
        n0 = nrx; ok = 1;
        for (i = 0; i < 10; i = i + 1) send(pat[9 - i]);
        idle_bits(1);
        for (i = 0; i < 10; i = i + 1) if (got[(n0 + i) % 256] !== pat[9 - i]) ok = 0;
        check(ok && nrx == n0 + 10, "10 back-to-back frames received");

        // ---- 4. sender baud error +-3 %
        n0 = nrx;
        send_bits(8'hB7, 0.97, 1'b1); send_bits(8'h4E, 0.97, 1'b1); idle_bits(1);
        send_bits(8'hB7, 1.03, 1'b1); send_bits(8'h4E, 1.03, 1'b1); idle_bits(1);
        check(nrx == n0 + 4 && got[n0 % 256] === 8'hB7 && got[(n0+1) % 256] === 8'h4E &&
              got[(n0+2) % 256] === 8'hB7 && got[(n0+3) % 256] === 8'h4E, "+-3% sender baud error tolerated");

        // ---- 5. framing error (stop bit low): no valid, one frame_err, receiver recovers
        n0 = nrx; f0 = nfe;
        send_bits(8'h5A, 1.0, 1'b0); idle_bits(2);
        check(nrx == n0 && nfe == f0 + 1, "stop bit low: frame_err, no valid");
        send(8'h6B); idle_bits(1);
        check(nrx == n0 + 1 && got[n0 % 256] === 8'h6B, "good frame after a framing error");

        // ---- 6. line stuck low (break): exactly one frame_err, then recovery
        n0 = nrx; f0 = nfe;
        rx = 1'b0; #(BIT_NS * 25); rx = 1'b1; #(BIT_NS * 2);
        check(nrx == n0 && nfe == f0 + 1, "break (25 bit times low): a single frame_err");
        send(8'h9D); idle_bits(1);
        check(nrx == n0 + 1 && got[n0 % 256] === 8'h9D, "good frame after a break");

        // ---- 7. start-bit glitch (quarter bit low) is ignored
        n0 = nrx; f0 = nfe;
        rx = 1'b0; #(BIT_NS * 0.25); rx = 1'b1; #(BIT_NS * 3);
        check(nrx == n0 && nfe == f0 && busy === 1'b0, "start-bit glitch ignored");
        send(8'h2F); idle_bits(1);
        check(nrx == n0 + 1 && got[n0 % 256] === 8'h2F, "good frame after a glitch");

        // ---- 8. reset in the middle of a frame (sender then abandons the frame, line idle)
        n0 = nrx; f0 = nfe;
        rx = 1'b0; #(BIT_NS * 3.5);                     // start bit + 2 data bits (all zero)
        check(busy === 1'b1, "frame in progress before reset");
        rst = 1; rx = 1'b1; #(T * 4); rst = 0; #(BIT_NS * 3);
        check(busy === 1'b0 && nrx == n0 && nfe == f0, "reset mid-frame: idle, no valid, no frame_err");
        send(8'hE1); idle_bits(1);
        check(nrx == n0 + 1 && got[n0 % 256] === 8'hE1, "good frame after a mid-frame reset");

        check(wide == 0, "valid never wider than one clock (whole run)");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #(BIT_NS * 4000 + 1_000_000); $display("FAIL  global watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
