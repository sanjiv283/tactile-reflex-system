`timescale 1ns / 1ps
// Stage 3 top: UART LUT upload in front of the unchanged Stage 2 top (reflex_top_spi).
//   uart_rx -> lut_upload_ctrl -> reflex_top_spi.lut_wr_* / lut_swap
// reflex_top_spi, reflex_top and lut_engine are used unchanged; the only coupling is their
// existing lut_wr_en / lut_wr_addr / lut_wr_data / lut_swap ports.
// CLK_HZ, BAUD and UPLOAD_TIMEOUT_US are PLACEHOLDERS: set them for the real board and host.
// No board pins are assumed here; uart_rxd and uart_txd are plain ports.
// Stage 4 (additive): uart_tx + upload_resp_tx send a 4-byte response frame to the host for every
// upload ack/nak (format in upload_resp_tx.v). Existing ports and behaviour are unchanged.
module reflex_top_uart #(
    parameter CLK_HZ            = 100_000_000,
    parameter BAUD              = 115200,
    parameter UPLOAD_TIMEOUT_US = 10_000,
    parameter RESP_FIFO_DEPTH   = 4,         // Stage 4: FIFO slots; 1 more response is held while its frame is sent
    parameter SCLK_HZ           = 1_000_000,
    parameter FRAME_US          = 20_000,
    parameter LUT_INIT_FILE     = ""
)(
    input  wire        clk,
    input  wire        rst_btn,
    input  wire        estop_btn,
    input  wire        grip_en_sw,
    // UART from the host (asynchronous, synchronized inside uart_rx)
    input  wire        uart_rxd,
    // MCP3008
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        servo_out,
    output wire [3:0]  fault_led,
    output wire        active_bank_led,
    output wire        dbg_cmd_toggle,
    output wire        adc_frame_err,
    // upload status (no uart_tx yet: use LEDs/probes)
    output wire        upload_ack,
    output wire        upload_nak,
    output wire [3:0]  upload_err,
    output wire        upload_active,
    output wire        upload_failed,
    output wire [6:0]  upload_entries,
    output wire        upload_commit,
    // Stage 4: serial responses to the host
    output wire        uart_txd,
    output wire        tx_busy,
    output wire        resp_overflow
);
    // same 2-flop reset synchronizer as reflex_top / reflex_top_spi
    reg [1:0] rst_s = 2'b11;
    always @(posedge clk) rst_s <= {rst_s[0], rst_btn};
    wire rst = rst_s[1];

    wire [7:0]  rx_data;
    wire        rx_valid, rx_ferr, rx_busy;
    wire        wr_en, swap;
    wire [5:0]  wr_addr;
    wire [11:0] wr_data;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_rxd),
        .data(rx_data), .valid(rx_valid), .frame_err(rx_ferr), .busy(rx_busy)
    );

    lut_upload_ctrl #(.CLK_HZ(CLK_HZ), .TIMEOUT_US(UPLOAD_TIMEOUT_US)) u_up (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_ferr),
        .lut_wr_en(wr_en), .lut_wr_addr(wr_addr), .lut_wr_data(wr_data), .lut_swap(swap),
        .ack(upload_ack), .nak(upload_nak), .err_code(upload_err), .commit_done(upload_commit),
        .upload_active(upload_active), .upload_failed(upload_failed), .entries(upload_entries)
    );

    // Stage 4: responses to the host
    wire [7:0] tx_data;
    wire       tx_valid, tx_ready, resp_busy;

    upload_resp_tx #(.DEPTH(RESP_FIFO_DEPTH)) u_resp (
        .clk(clk), .rst(rst),
        .ev_ack(upload_ack), .ev_nak(upload_nak), .ev_commit(upload_commit),
        .ev_err(upload_err), .ev_entries(upload_entries),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .overflow(resp_overflow), .busy(resp_busy)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx(uart_txd), .busy(tx_busy)
    );

    reflex_top_spi #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ), .FRAME_US(FRAME_US),
                     .LUT_INIT_FILE(LUT_INIT_FILE)) u_spi (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .lut_wr_en(wr_en), .lut_wr_addr(wr_addr), .lut_wr_data(wr_data), .lut_swap(swap),
        .servo_out(servo_out), .fault_led(fault_led),
        .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle),
        .adc_frame_err(adc_frame_err)
    );
endmodule
