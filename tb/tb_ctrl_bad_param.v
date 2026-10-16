`timescale 1ns / 1ps
// NEGATIVE TEST - this file MUST FAIL to compile/elaborate.
// PULSE_MIN above PULSE_MAX is not a valid pulse window (rtl/lut_upload_ctrl.v rejects it).
module tb_ctrl_bad_param;
    wire we, sw, ack, nak, cd, act, fl; wire [5:0] wa; wire [11:0] wd; wire [3:0] e; wire [6:0] n;
    lut_upload_ctrl #(.PULSE_MIN(2000), .PULSE_MAX(1000)) dut (
        .clk(1'b0), .rst(1'b1), .rx_data(8'd0), .rx_valid(1'b0), .rx_frame_err(1'b0),
        .lut_wr_en(we), .lut_wr_addr(wa), .lut_wr_data(wd), .lut_swap(sw),
        .ack(ack), .nak(nak), .err_code(e), .commit_done(cd), .upload_active(act), .upload_failed(fl), .entries(n));
endmodule
