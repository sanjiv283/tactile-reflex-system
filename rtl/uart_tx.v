`timescale 1ns / 1ps
// UART transmitter, 8N1, LSB first. Stage 4.
//
// CLK_HZ and BAUD are PLACEHOLDER defaults (100 MHz, 115200), the same parameters and the same
// rounding as uart_rx: CLKS_PER_BIT = round(CLK_HZ / BAUD) must be >= 8 (otherwise elaboration
// fails). Every bit lasts exactly CLKS_PER_BIT clocks, so the real baud rate differs from BAUD
// by the rounding error only (868 vs 868.05 at 100 MHz/115200 = 0.006 %; 234 vs 234.375 at
// 27 MHz/115200 = 0.16 %).
//
// Handshake: the byte on tx_data is accepted on a clock edge where tx_valid && tx_ready.
//  - tx_ready is high when idle and ALSO during the last clock of the stop bit, so a producer
//    that keeps tx_valid high with the next byte gets a continuous stream: stop bit, then the
//    next start bit immediately (10 bit times per byte, no gap).
//  - busy is high from the accepted byte until the stop bit has ended with nothing queued.
// The line (tx) idles high. rst (synchronous, active high) abandons a frame in progress: tx is
// high from the next clock, so a receiver sees a truncated (possibly framing-error) byte at most.
module uart_tx #(
    parameter CLK_HZ = 100_000_000,   // PLACEHOLDER: board clock
    parameter BAUD   = 115200         // PLACEHOLDER: host baud rate
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,
    output reg        tx,
    output wire       busy
);
    localparam CPB = (CLK_HZ + BAUD/2) / BAUD;   // clocks per bit, rounded (same as uart_rx)
    localparam CW  = $clog2(CPB + 1);

    generate
        if (BAUD < 1 || CPB < 8) begin : g_bad_params
            UART_TX_invalid_CLK_HZ_or_BAUD u_param_check ();
        end
    endgenerate

    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0]    st;
    reg [CW-1:0] cnt;
    reg [2:0]    bitn;
    reg [7:0]    sh;

    assign tx_ready = (st == S_IDLE) || (st == S_STOP && cnt == CPB - 1);
    assign busy     = (st != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; cnt <= 0; bitn <= 0; sh <= 8'hFF; tx <= 1'b1;
        end else case (st)
            S_IDLE:  if (tx_valid) begin sh <= tx_data; tx <= 1'b0; cnt <= 0; st <= S_START; end
            S_START: if (cnt == CPB - 1) begin
                         cnt <= 0; tx <= sh[0]; sh <= {1'b1, sh[7:1]}; bitn <= 0; st <= S_DATA;
                     end else cnt <= cnt + 1'b1;
            S_DATA:  if (cnt == CPB - 1) begin
                         cnt <= 0;
                         if (bitn == 3'd7) begin tx <= 1'b1; st <= S_STOP; end
                         else begin tx <= sh[0]; sh <= {1'b1, sh[7:1]}; bitn <= bitn + 1'b1; end
                     end else cnt <= cnt + 1'b1;
            S_STOP:  if (cnt == CPB - 1) begin
                         cnt <= 0;
                         if (tx_valid) begin sh <= tx_data; tx <= 1'b0; st <= S_START; end
                         else st <= S_IDLE;
                     end else cnt <= cnt + 1'b1;
        endcase
    end
endmodule
