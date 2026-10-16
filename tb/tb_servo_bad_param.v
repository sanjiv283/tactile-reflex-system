`timescale 1ns / 1ps
// NEGATIVE / BOUNDARY TEST for rtl/servo_pwm_generator.v - selected with -D<CASE> by run_sim.sh.
//   BAD_CLK_LOW, BAD_CLK_FRAC, BAD_FRAME  : each MUST FAIL to elaborate, through its own guard
//   BAD_TOP_FRAME                         : the same FRAME_US guard reached through reflex_top (inheritance)
//   OK_MIN                                : smallest accepted configuration, MUST elaborate
//   OK_TOP_FRAME                          : the BAD_TOP_FRAME instantiation with FRAME_US = 2001, MUST elaborate
module tb_servo_bad_param;
    wire o;
`ifdef BAD_CLK_LOW
    servo_pwm_generator #(.CLK_HZ(500_000), .FRAME_US(20_000)) dut (.clk(1'b0), .rst(1'b1), .pulse_us(12'd1500), .servo_out(o));
`elsif BAD_CLK_FRAC
    servo_pwm_generator #(.CLK_HZ(1_500_000), .FRAME_US(20_000)) dut (.clk(1'b0), .rst(1'b1), .pulse_us(12'd1500), .servo_out(o));
`elsif BAD_FRAME
    servo_pwm_generator #(.CLK_HZ(1_000_000), .FRAME_US(2000)) dut (.clk(1'b0), .rst(1'b1), .pulse_us(12'd1500), .servo_out(o));
`elsif BAD_TOP_FRAME
    wire [3:0] f; wire b, t;
    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2000)) dut (
        .clk(1'b0), .rst_btn(1'b1), .estop_btn(1'b0), .grip_en_sw(1'b1), .adc_value(10'd0), .adc_valid(1'b0),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(o), .fault_led(f), .active_bank_led(b), .dbg_cmd_toggle(t));
`elsif OK_TOP_FRAME
    wire [3:0] f; wire b, t;
    reflex_top #(.CLK_HZ(1_000_000), .FRAME_US(2001)) dut (
        .clk(1'b0), .rst_btn(1'b1), .estop_btn(1'b0), .grip_en_sw(1'b1), .adc_value(10'd0), .adc_valid(1'b0),
        .lut_wr_en(1'b0), .lut_wr_addr(6'd0), .lut_wr_data(12'd0), .lut_swap(1'b0),
        .servo_out(o), .fault_led(f), .active_bank_led(b), .dbg_cmd_toggle(t));
`elsif OK_MIN
    servo_pwm_generator #(.CLK_HZ(1_000_000), .FRAME_US(2001)) dut (.clk(1'b0), .rst(1'b1), .pulse_us(12'd2000), .servo_out(o));
`else
    initial $display("tb_servo_bad_param: define one case");
    UNDEFINED_CASE_SELECTOR u_must_fail ();
`endif
endmodule
