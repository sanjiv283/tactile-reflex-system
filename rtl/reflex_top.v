`timescale 1ns / 1ps
// Stage 1 top level. Critical path: ADC sample -> LUT -> safety -> PWM.
// No CPU, no software in this path.
// Stage 2 will replace the adc_value/adc_valid ports with adc_spi_interface.
// Stage 3 will drive the lut_wr_* / lut_swap ports from uart_rx.
module reflex_top #(
    parameter CLK_HZ        = 100_000_000,
    parameter FRAME_US      = 20_000,
    parameter LUT_INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst_btn,
    input  wire        estop_btn,
    input  wire        grip_en_sw,
    input  wire [9:0]  adc_value,
    input  wire        adc_valid,
    input  wire        lut_wr_en,
    input  wire [5:0]  lut_wr_addr,
    input  wire [11:0] lut_wr_data,
    input  wire        lut_swap,
    output wire        servo_out,
    output wire [3:0]  fault_led,
    output wire        active_bank_led,
    output wire        dbg_cmd_toggle
);
    // 2-flop synchronizers for the asynchronous buttons/switches
    reg [1:0] rst_s = 2'b11, estop_s = 2'b00, grip_s = 2'b00;
    always @(posedge clk) begin
        rst_s   <= {rst_s[0],   rst_btn};
        estop_s <= {estop_s[0], estop_btn};
        grip_s  <= {grip_s[0],  grip_en_sw};
    end
    wire rst = rst_s[1];

    wire [11:0] lut_pulse_us, pulse_cmd;
    wire        lut_valid;

    lut_engine #(.INIT_FILE(LUT_INIT_FILE)) u_lut (
        .clk(clk), .rst(rst),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_pulse_us(lut_pulse_us), .lut_valid(lut_valid),
        .wr_en(lut_wr_en), .wr_addr(lut_wr_addr), .wr_data(lut_wr_data),
        .swap(lut_swap), .active_bank(active_bank_led)
    );

    safety_governor #(.CLK_HZ(CLK_HZ)) u_gov (
        .clk(clk), .rst(rst),
        .estop(estop_s[1]), .grip_en(grip_s[1]),
        .adc_value(adc_value), .adc_valid(adc_valid),
        .lut_pulse_us(lut_pulse_us), .lut_valid(lut_valid),
        .pulse_us(pulse_cmd), .cmd_toggle(dbg_cmd_toggle), .fault(fault_led)
    );

    servo_pwm_generator #(.CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US)) u_pwm (
        .clk(clk), .rst(rst), .pulse_us(pulse_cmd), .servo_out(servo_out)
    );
endmodule
