`timescale 1ns / 1ps
// LUT upload controller. Stage 3. Turns a byte stream (from uart_rx) into writes to the
// INACTIVE bank of lut_engine and, only after a complete valid upload, one bank swap.
// Drives lut_engine's existing wr_en / wr_addr / wr_data / swap ports; lut_engine is unchanged.
//
// ---------------------------------------------------------------- PACKET FORMAT (host -> FPGA)
//   0xA5 | CMD | payload (fixed length per CMD) | CHK        CHK = CMD ^ every payload byte
//   CMD 0x01 BEGIN   payload: none                  start an upload, forget everything received
//   CMD 0x02 WRITE   payload: ADDR DATA_H DATA_L    entry ADDR (0..63) = {DATA_H[3:0], DATA_L} (us)
//   CMD 0x03 COMMIT  payload: none                  swap banks, only if the upload is complete
//   CMD 0x04 ABORT   payload: none                  cancel the upload, no swap
//   There is no length byte and no byte stuffing: 0xA5 is an ordinary data value inside a packet.
//   XOR detects any single-byte error and any odd number of flipped bits in one bit position, but
//   NOT swapped/compensating errors (e.g. two bytes changing in the same bit). It is an integrity
//   check against line noise, not security: there is no authentication.
//
// ---------------------------------------------------------------- RULES
//  Upload state: idle -> (BEGIN) active -> (COMMIT ok) idle, or -> failed. A WRITE is only accepted
//  in an active, not-failed upload. WRITE data must satisfy PULSE_MIN <= value <= PULSE_MAX and
//  DATA_H[7:4] == 0, ADDR < 64. COMMIT swaps ONLY when all 64 DISTINCT addresses have been written
//  (duplicate WRITEs to one address are accepted but count once), no NAK has occurred since BEGIN,
//  and the upload is active. Partial updates are never swapped in: the inactive bank holds the OLD
//  table, so a swap with missing entries would bring stale values back.
//  Any NAK while an upload is active marks it FAILED: later WRITE/COMMIT are refused (ERR_FAILED)
//  until a new BEGIN. BEGIN always restarts; ABORT always cancels (both ACK, even if already failed).
//  The live table (active bank) is never written: it changes only through the single lut_swap pulse
//  of a successful COMMIT, one clock after nothing else is writing.
//
// ---------------------------------------------------------------- FRAMING AND RECOVERY
//  S_SOF   : every byte other than 0xA5 is ignored (leading garbage is skipped). No timeout here:
//            an idle gap BETWEEN packets is fine and does not cancel an upload.
//  inside a packet (CMD / payload / CHK): a gap of TIMEOUT_US without a byte aborts the packet:
//            NAK ERR_TIMEOUT, upload (if any) FAILED, back to S_SOF (the line is already idle).
//  QUIET   : entered after errors where packet boundaries can no longer be trusted:
//            checksum mismatch, unknown CMD, UART frame error. All bytes are ignored (no ACK/NAK)
//            until the line has been idle for TIMEOUT_US, then S_SOF. This is what keeps a 0xA5
//            inside a corrupted packet from being taken as a new start. CONSEQUENCE: after such an
//            error the host must pause >= TIMEOUT_US before its next packet (a packet sent
//            sooner is swallowed). Errors detected on a complete, checksum-valid packet
//            (bad address/data, wrong state, incomplete COMMIT) go straight back to S_SOF.
//  Reset: clears the packet parser, the received-address set and the active/failed flags. The
//            live table is unaffected. Whatever the reset interrupted needs a fresh BEGIN.
//  TIMEOUT_US must exceed the host's longest gap between two bytes of one packet. It is a
//  PLACEHOLDER (10 ms). CLK_HZ must be a whole number of MHz.
//
// ---------------------------------------------------------------- STATUS / FEEDBACK
//  There is no transmit path (no uart_tx yet). ack / nak are 1-clock pulses, err_code holds the
//  last NAK reason (cleared by BEGIN and reset). Wire them to LEDs/probes until a uart_tx exists.
//  err_code: 0 none, 1 CHK, 2 CMD, 3 NOT_ACTIVE, 4 FAILED, 5 ADDR, 6 DATA(upper nibble), 7 RANGE,
//            8 INCOMPLETE, 9 TIMEOUT, 10 UART (framing error)
module lut_upload_ctrl #(
    parameter CLK_HZ     = 100_000_000,   // PLACEHOLDER; whole MHz
    parameter TIMEOUT_US = 10_000,        // PLACEHOLDER: inter-byte / quiet time
    parameter PULSE_MIN  = 1000,          // keep equal to safety_governor PULSE_MIN_US
    parameter PULSE_MAX  = 2000           // keep equal to safety_governor PULSE_MAX_US
)(
    input  wire        clk,
    input  wire        rst,
    // from uart_rx
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_frame_err,
    // to lut_engine
    output reg         lut_wr_en,
    output reg  [5:0]  lut_wr_addr,
    output reg  [11:0] lut_wr_data,
    output reg         lut_swap,
    // status
    output reg         ack,
    output reg         nak,
    output reg  [3:0]  err_code,
    output reg         commit_done,
    output wire        upload_active,
    output wire        upload_failed,
    output wire [6:0]  entries            // distinct addresses received (0..64)
);
    generate
        if (PULSE_MIN > PULSE_MAX || PULSE_MAX > 4095 || TIMEOUT_US < 1) begin : g_bad_params
            LUT_UPLOAD_CTRL_invalid_parameters u_param_check ();
        end
    endgenerate

    localparam [7:0] SOF = 8'hA5;
    localparam [7:0] C_BEGIN = 8'h01, C_WRITE = 8'h02, C_COMMIT = 8'h03, C_ABORT = 8'h04;
    localparam [3:0] E_CHK = 1, E_CMD = 2, E_NOT_ACTIVE = 3, E_FAILED = 4, E_ADDR = 5,
                     E_DATA = 6, E_RANGE = 7, E_INCOMPLETE = 8, E_TIMEOUT = 9, E_UART = 10;
    localparam [2:0] S_SOF = 0, S_CMD = 1, S_PAY = 2, S_CHK = 3, S_QUIET = 4;
    localparam integer TLIM = TIMEOUT_US * (CLK_HZ / 1_000_000);

    reg [2:0]  st;
    reg [7:0]  cmd, p0, p1, p2;
    reg [1:0]  pidx;
    reg [31:0] idle;
    reg [63:0] seen;
    reg [6:0]  cnt;
    reg        act, fail;

    assign upload_active = act;
    assign upload_failed = fail;
    assign entries       = cnt;

    wire [7:0]  xsum = cmd ^ ((cmd == C_WRITE) ? (p0 ^ p1 ^ p2) : 8'h00);
    wire [11:0] wval = {p1[3:0], p2};
    wire        in_packet = (st == S_CMD) || (st == S_PAY) || (st == S_CHK);

    task reject(input [3:0] code);
        begin nak <= 1'b1; err_code <= code; if (act) fail <= 1'b1; end
    endtask

    always @(posedge clk) begin
        lut_wr_en <= 1'b0; lut_swap <= 1'b0; ack <= 1'b0; nak <= 1'b0; commit_done <= 1'b0;
        if (rst) begin
            st <= S_SOF; cmd <= 0; p0 <= 0; p1 <= 0; p2 <= 0; pidx <= 0; idle <= 0;
            seen <= 64'd0; cnt <= 0; act <= 1'b0; fail <= 1'b0; err_code <= 0;
            lut_wr_addr <= 0; lut_wr_data <= 0;
        end else begin
            if (rx_valid || rx_frame_err) idle <= 0;
            else if (idle < TLIM) idle <= idle + 1;

            if (rx_frame_err) begin                           // any state: framing can't be trusted
                reject(E_UART); st <= S_QUIET;
            end else if (rx_valid) begin
                case (st)
                    S_SOF: if (rx_data == SOF) st <= S_CMD;
                    S_CMD: begin
                        cmd <= rx_data; pidx <= 0;
                        case (rx_data)
                            C_BEGIN, C_COMMIT, C_ABORT: st <= S_CHK;
                            C_WRITE:                    st <= S_PAY;
                            default: begin reject(E_CMD); st <= S_QUIET; end
                        endcase
                    end
                    S_PAY: begin
                        case (pidx) 2'd0: p0 <= rx_data; 2'd1: p1 <= rx_data; default: p2 <= rx_data; endcase
                        pidx <= pidx + 1'b1;
                        if (pidx == 2'd2) st <= S_CHK;
                    end
                    S_CHK: begin
                        if (rx_data != xsum) begin
                            reject(E_CHK); st <= S_QUIET;
                        end else begin
                            st <= S_SOF;
                            case (cmd)
                                C_BEGIN: begin
                                    act <= 1'b1; fail <= 1'b0; seen <= 64'd0; cnt <= 0;
                                    err_code <= 0; ack <= 1'b1;
                                end
                                C_ABORT: begin act <= 1'b0; fail <= 1'b0; ack <= 1'b1; end
                                C_WRITE:
                                    if (!act)                       reject(E_NOT_ACTIVE);
                                    else if (fail)                  reject(E_FAILED);
                                    else if (p0 >= 8'd64)           reject(E_ADDR);
                                    else if (p1[7:4] != 4'd0)       reject(E_DATA);
                                    else if (wval < PULSE_MIN || wval > PULSE_MAX) reject(E_RANGE);
                                    else begin
                                        lut_wr_en <= 1'b1; lut_wr_addr <= p0[5:0]; lut_wr_data <= wval;
                                        if (!seen[p0[5:0]]) begin seen[p0[5:0]] <= 1'b1; cnt <= cnt + 1'b1; end
                                        ack <= 1'b1;
                                    end
                                C_COMMIT:
                                    if (!act)                       reject(E_NOT_ACTIVE);
                                    else if (fail)                  reject(E_FAILED);
                                    else if (!(&seen))              reject(E_INCOMPLETE);
                                    else begin
                                        lut_swap <= 1'b1; commit_done <= 1'b1; act <= 1'b0; ack <= 1'b1;
                                    end
                                default: ;
                            endcase
                        end
                    end
                    default: ;                                     // S_QUIET: ignore the byte
                endcase
            end else if (in_packet && idle >= TLIM) begin       // gap inside a packet
                reject(E_TIMEOUT); st <= S_SOF;
            end else if (st == S_QUIET && idle >= TLIM) begin   // line quiet long enough
                st <= S_SOF;
            end
        end
    end
endmodule
