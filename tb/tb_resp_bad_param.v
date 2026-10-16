`timescale 1ns / 1ps
// NEGATIVE TEST - this file MUST FAIL to compile/elaborate.
// A response FIFO needs DEPTH >= 2 (rtl/upload_resp_tx.v rejects anything smaller).
module tb_resp_bad_param;
    wire [7:0] d; wire v, o, b;
    upload_resp_tx #(.DEPTH(1)) dut (
        .clk(1'b0), .rst(1'b1), .ev_ack(1'b0), .ev_nak(1'b0), .ev_commit(1'b0), .ev_err(4'd0), .ev_entries(7'd0),
        .tx_data(d), .tx_valid(v), .tx_ready(1'b1), .overflow(o), .busy(b));
endmodule
