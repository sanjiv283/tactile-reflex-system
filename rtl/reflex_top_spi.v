// Stage 2 top: MCP3008 SPI interface feeding the unchanged reflex_top.
// Continuous sampling of channel 0; a request is issued only when the interface is idle.
// Only data_valid (a completed frame with null bit = 0) reaches the governor's timeout
// timer; requests and frame_err frames never do.
module reflex_top_spi #(
    parameter CLK_HZ   = 100_000_000,
    parameter SCLK_HZ  = 1_000_000,
    parameter FRAME_US = 20000
) (
    input         clk,
    input         rst,
    input         estop,
    input         miso,
    output        cs_n,
    output        sclk,
    output        mosi,
    output        servo_pwm,
    output [11:0] pulse_cmd,
    output        dbg_cmd_toggle,
    output        safe_state,
    output        over_force,
    output        fault_range,
    output        fault_timeout,
    output        fault_estop,
    output        adc_frame_err
);
    // Copy of safety_governor's default timeout (reflex_top does not expose it): keep in sync.
    localparam integer ADC_TIMEOUT_US = 1000;
    localparam integer HALF           = (CLK_HZ + 2 * SCLK_HZ - 1) / (2 * SCLK_HZ);
    localparam integer FRAME_CLKS     = 36 * HALF + 2;       // generous upper bound per conversion
    generate if (ADC_TIMEOUT_US * (CLK_HZ / 1_000_000) < 4 * FRAME_CLKS) begin : bad_timeout
        reflex_top_spi_sclk_too_slow_for_adc_timeout u_err();
    end endgenerate

    wire        busy, data_valid;
    wire [9:0]  data;

    adc_spi_interface #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_adc (
        .clk(clk), .rst(rst), .start(~busy), .channel(3'd0), .miso(miso),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .busy(busy),
        .data(data), .data_valid(data_valid), .frame_err(adc_frame_err));

    reflex_top #(.CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US)) u_core (
        .clk(clk), .rst(rst), .adc_value(data), .adc_valid(data_valid), .estop(estop),
        .servo_pwm(servo_pwm), .pulse_cmd(pulse_cmd), .dbg_cmd_toggle(dbg_cmd_toggle),
        .safe_state(safe_state), .over_force(over_force), .fault_range(fault_range),
        .fault_timeout(fault_timeout), .fault_estop(fault_estop));
endmodule
