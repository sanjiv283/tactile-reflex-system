`timescale 1ns / 1ps
// Host response formatter. Stage 4. Turns lut_upload_ctrl's ack / nak events into serial frames.
//
// ---------------------------------------------------------------- RESPONSE FRAME (FPGA -> host)
//   0x5A | STATUS | INFO | CHK            CHK = STATUS ^ INFO
//   STATUS 0x06  ACK        command accepted.                    INFO = distinct entries received (0..64)
//   STATUS 0x07  COMMITTED  COMMIT accepted and the swap happened. INFO = 64
//   STATUS 0x15  NAK        command rejected.                    INFO = error code (same as err_code):
//                           1 CHK, 2 CMD, 3 NOT_ACTIVE, 4 FAILED, 5 ADDR, 6 DATA, 7 RANGE,
//                           8 INCOMPLETE, 9 TIMEOUT, 10 UART
//   STATUS bit 7 (0x80) set: one or more earlier responses were DROPPED (FIFO full) right before
//                           this one. The flag is attached to the next response that is queued.
//   0x5A never appears anywhere in a frame except as its first byte (INFO <= 64, STATUS is one of
//   0x06 0x07 0x15 | 0x80, and STATUS ^ INFO is never 0x5A), so a host resynchronises on 0x5A.
//   Host parser: hunt for 0x5A; read STATUS, INFO, CHK; a 0x5A seen in place of any of those bytes
//   starts a new frame (truncated frame); a bad CHK or an impossible STATUS/INFO drops the frame.
//   No command echo: the host matches responses to commands by order, except error codes 9
//   (timeout) and 10 (UART framing error), which are asynchronous events with no command of
//   their own. Packets the controller ignores (garbage before 0xA5, packets swallowed during the
//   quiet period) produce NO response.
//
// ---------------------------------------------------------------- QUEUEING
//   Each ack/nak event is pushed into a FIFO of DEPTH entries and sent in order, one frame at a
//   time, back to back (no gap between frames while the queue is non-empty).
//   A response is stored in exactly one place at a time:
//     - waiting: one of the DEPTH FIFO slots;
//     - being sent: the separate `cur` register, from the clock it is popped (it leaves the FIFO
//       in that same clock, so it is never counted in both places) until its fourth and last
//       byte has been handed to uart_tx. That last byte then finishes inside uart_tx's own shift
//       register and uses no response storage.
//   A new response is accepted only if a FIFO slot is free; `cur` is not part of that test.
//   So the storage capacity is DEPTH waiting + 1 being sent = DEPTH+1 responses: a burst that
//   arrives faster than a frame can start (e.g. one event per clock into an idle, empty queue)
//   is accepted up to DEPTH+1 responses (5 for DEPTH = 4) and the rest are dropped. Under
//   sustained traffic more are accepted in total, because frames keep leaving. At one instant up
//   to DEPTH+2 responses can still have bytes to send: the previous frame's last byte is still on
//   the wire while the next frame is in `cur` and the FIFO is full.
//   A 4-byte reply to a 3-byte command (BEGIN/COMMIT/ABORT) is slower than the commands, so a
//   long burst of short commands can fill the FIFO. A response arriving while the FIFO is full
//   is DROPPED (never reordered); the next response that is queued then carries the lost flag
//   (STATUS bit 7), and the sticky `overflow` output is set until reset. WRITE (6 bytes in,
//   4 bytes out) cannot overflow the queue.
//   Reset empties the FIFO, forgets any pending lost flag and stops transmitting at once (a frame
//   in flight is cut off: the host sees a truncated frame and resynchronises on the next 0x5A).
// DEPTH must be >= 2.
module upload_resp_tx #(
    parameter DEPTH = 4
)(
    input  wire       clk,
    input  wire       rst,
    // events from lut_upload_ctrl (1-clock pulses, values valid in the same clock)
    input  wire       ev_ack,
    input  wire       ev_nak,
    input  wire       ev_commit,       // with ev_ack: the ACK is a COMMIT that swapped
    input  wire [3:0] ev_err,
    input  wire [6:0] ev_entries,
    // to uart_tx
    output wire [7:0] tx_data,
    output wire       tx_valid,
    input  wire       tx_ready,
    // status
    output reg        overflow,        // sticky: at least one response was dropped
    output wire       busy             // a frame is being sent or queued
);
    generate
        if (DEPTH < 2) begin : g_bad_params
            UPLOAD_RESP_TX_invalid_DEPTH u_param_check ();
        end
    endgenerate

    localparam AW = $clog2(DEPTH);
    localparam [7:0] SOF = 8'h5A;
    localparam [1:0] K_ACK = 2'd0, K_COMMIT = 2'd1, K_NAK = 2'd2;

    reg [9:0]    mem [0:DEPTH-1];            // {lost, kind[1:0], info[6:0]}
    reg [AW-1:0] wp, rp;
    reg [AW:0]   count;
    reg          lost_pend;

    reg          sending;                    // a frame is being sent
    reg [1:0]    idx;
    reg [9:0]    cur;

    wire ev       = ev_ack | ev_nak;
    wire push     = ev && (count < DEPTH);
    wire pop      = !sending && (count != 0);
    wire [1:0] ev_kind = ev_nak ? K_NAK : (ev_commit ? K_COMMIT : K_ACK);
    wire [6:0] ev_info = ev_nak ? {3'b000, ev_err} : ev_entries;

    wire [7:0] status = ((cur[8:7] == K_ACK) ? 8'h06 : (cur[8:7] == K_COMMIT) ? 8'h07 : 8'h15)
                        | (cur[9] ? 8'h80 : 8'h00);
    wire [7:0] info   = {1'b0, cur[6:0]};

    assign tx_valid = sending;
    assign tx_data  = (idx == 2'd0) ? SOF :
                      (idx == 2'd1) ? status :
                      (idx == 2'd2) ? info : (status ^ info);
    assign busy     = sending || (count != 0);

    always @(posedge clk) begin
        if (rst) begin
            wp <= 0; rp <= 0; count <= 0; lost_pend <= 1'b0; overflow <= 1'b0;
            sending <= 1'b0; idx <= 0; cur <= 0;
        end else begin
            if (push) begin
                mem[wp] <= {lost_pend, ev_kind, ev_info};
                wp <= (wp == DEPTH - 1) ? {AW{1'b0}} : wp + 1'b1;
                lost_pend <= 1'b0;
            end else if (ev) begin           // FIFO full: drop, remember for the next response
                lost_pend <= 1'b1; overflow <= 1'b1;
            end
            if (pop) begin
                cur <= mem[rp];
                rp  <= (rp == DEPTH - 1) ? {AW{1'b0}} : rp + 1'b1;
                idx <= 0; sending <= 1'b1;
            end
            count <= count + (push ? 1'b1 : 1'b0) - (pop ? 1'b1 : 1'b0);
            if (sending && tx_ready) begin
                idx <= idx + 1'b1;
                if (idx == 2'd3) sending <= 1'b0;
            end
        end
    end
endmodule
