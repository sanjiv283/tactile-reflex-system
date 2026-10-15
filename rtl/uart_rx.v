`timescale 1ns / 1ps
// UART receiver, 8N1, LSB first. Stage 3.
//
// CLK_HZ and BAUD are PLACEHOLDER defaults (100 MHz, 115200): set them for the real board/host.
// CLKS_PER_BIT = round(CLK_HZ / BAUD) must be >= 8 (otherwise elaboration fails).
// The line is sampled in the middle of every bit through a 2-flop synchronizer.
//
// Behaviour
//  - Start bit: the line must still be low half a bit after the falling edge, otherwise the
//    pulse is treated as a glitch and ignored (no valid, no frame_err).
//  - valid     : 1-clock pulse, data[7:0] holds the received byte (stable until the next byte).
//  - frame_err : 1-clock pulse when the stop bit reads low. No valid pulse for that frame. The
//                receiver then waits for the line to return high before looking for a new start
//                bit, so a stuck-low line (break) produces ONE frame_err, not a stream of them.
//  - Back-to-back frames (no idle time between stop bit and next start bit) are received.
//  - rst (synchronous, active high) abandons any frame in progress and returns to idle.
//    After a reset the line is expected to be idle (high); a line held low through the reset
//    is seen as a new start bit.
//  - busy is high while a frame is being received.
module uart_rx #(
    parameter CLK_HZ = 100_000_000,   // PLACEHOLDER: board clock
    parameter BAUD   = 115200         // PLACEHOLDER: host baud rate
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        frame_err,
    output wire       busy
);
    localparam CPB   = (CLK_HZ + BAUD/2) / BAUD;   // clocks per bit, rounded
    localparam HALFB = CPB / 2;
    localparam CW    = $clog2(CPB + 1);

    generate
        if (BAUD < 1 || CPB < 8) begin : g_bad_params
            UART_RX_invalid_CLK_HZ_or_BAUD u_param_check ();
        end
    endgenerate

    localparam [2:0] S_IDLE = 3'd0, S_START = 3'd1, S_DATA = 3'd2, S_STOP = 3'd3, S_WAITHI = 3'd4;

    reg [2:0]    st;
    reg [CW-1:0] cnt;
    reg [2:0]    bitn;
    reg [7:0]    sh;
    reg          m1, ms;

    assign busy = (st != S_IDLE);

    always @(posedge clk) begin
        m1 <= rx; ms <= m1;
        valid <= 1'b0; frame_err <= 1'b0;
        if (rst) begin
            st <= S_IDLE; cnt <= 0; bitn <= 0; sh <= 0; data <= 0;
            m1 <= 1'b1; ms <= 1'b1;
        end else case (st)
            S_IDLE:  if (!ms) begin cnt <= 0; st <= S_START; end
            S_START: if (cnt == HALFB - 1) begin
                         cnt <= 0;
                         if (!ms) begin bitn <= 0; st <= S_DATA; end
                         else st <= S_IDLE;                      // glitch, not a start bit
                     end else cnt <= cnt + 1'b1;
            S_DATA:  if (cnt == CPB - 1) begin
                         cnt <= 0; sh <= {ms, sh[7:1]}; bitn <= bitn + 1'b1;
                         if (bitn == 3'd7) st <= S_STOP;
                     end else cnt <= cnt + 1'b1;
            S_STOP:  if (cnt == CPB - 1) begin
                         cnt <= 0;
                         if (ms) begin data <= sh; valid <= 1'b1; st <= S_IDLE; end
                         else    begin frame_err <= 1'b1; st <= S_WAITHI; end
                     end else cnt <= cnt + 1'b1;
            S_WAITHI: if (ms) st <= S_IDLE;
            default:  st <= S_IDLE;
        endcase
    end
endmodule
