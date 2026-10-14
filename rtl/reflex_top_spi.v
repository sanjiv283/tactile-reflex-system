`timescale 1ns / 1ps
// Stage 2 top: MCP3008 SPI interface feeding the UNCHANGED reflex_top.
// - Continuous sampling of channel 0. start = ~busy, so a request is only issued when the
//   interface is idle (the interface also ignores start while busy: two layers).
// - Only data_valid (completed frame, null bit = 0) reaches the governor's ADC-timeout timer.
//   Requests and frame_err frames never do, so a dead/disconnected ADC trips the timeout fault.
// - Same clock for both modules: no clock-domain crossing.
// - The interface gets the same 2-flop-synchronized reset as reflex_top's internal one.
module reflex_top_spi #(
    parameter CLK_HZ        = 100_000_000,
    parameter SCLK_HZ       = 1_000_000,
    parameter FRAME_US      = 20_000,
    parameter LUT_INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst_btn,
    input  wire        estop_btn,
    input  wire        grip_en_sw,
    // MCP3008
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    // LUT update port (Stage 3 will drive these from uart_rx)
    input  wire        lut_wr_en,
    input  wire [5:0]  lut_wr_addr,
    input  wire [11:0] lut_wr_data,
    input  wire        lut_swap,
    output wire        servo_out,
    output wire [3:0]  fault_led,
    output wire        active_bank_led,
    output wire        dbg_cmd_toggle,
    output wire        adc_frame_err
);
    // Copy of safety_governor's default ADC_TIMEOUT_US (reflex_top does not expose it).
    // If you change one, change both.
    localparam ADC_TIMEOUT_US = 1000;
    localparam HALF           = (CLK_HZ + 2*SCLK_HZ - 1) / (2*SCLK_HZ);
    localparam CONV_CLKS      = 35*HALF + 1;

    // A healthy sensor must deliver at least 4 samples per timeout window.
    generate
        if (ADC_TIMEOUT_US * (CLK_HZ / 1_000_000) < 4 * CONV_CLKS) begin : g_bad_timeout
            REFLEX_TOP_SPI_sclk_too_slow_for_adc_timeout u_timeout_check ();
        end
    endgenerate

    reg [1:0] rst_s = 2'b11;
    always @(posedge clk) rst_s <= {rst_s[0], rst_btn};
    wire rst = rst_s[1];

    wire       busy, data_valid;
    wire [9:0] data;
    wire [2:0] data_channel;   // unused: channel is fixed at 0

    adc_spi_interface #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_adc (
        .clk(clk), .rst(rst), .start(~busy), .channel(3'd0),
        .busy(busy), .data(data), .data_channel(data_channel),
        .data_valid(data_valid), .frame_err(adc_frame_err),
        .spi_cs_n(spi_cs_n), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    reflex_top #(.CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US), .LUT_INIT_FILE(LUT_INIT_FILE)) u_core (
        .clk(clk), .rst_btn(rst_btn), .estop_btn(estop_btn), .grip_en_sw(grip_en_sw),
        .adc_value(data), .adc_valid(data_valid),
        .lut_wr_en(lut_wr_en), .lut_wr_addr(lut_wr_addr), .lut_wr_data(lut_wr_data),
        .lut_swap(lut_swap),
        .servo_out(servo_out), .fault_led(fault_led),
        .active_bank_led(active_bank_led), .dbg_cmd_toggle(dbg_cmd_toggle)
    );
endmodule
