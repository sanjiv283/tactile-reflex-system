`timescale 1ns / 1ps
// Servo PWM: one high pulse of pulse_us microseconds every FRAME_US.
// pulse_us is latched once per frame, so the output never glitches mid-pulse.
module servo_pwm_generator #(
    parameter CLK_HZ   = 100_000_000,  // board clock (set per board)
    parameter FRAME_US = 20_000        // 20 ms = standard 50 Hz servo frame
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] pulse_us,
    output reg         servo_out
);
    localparam TICKS_PER_US = CLK_HZ / 1_000_000;
    localparam DIV_W = (TICKS_PER_US > 1) ? $clog2(TICKS_PER_US) : 1;
    localparam CNT_W = $clog2(FRAME_US);

    reg [DIV_W-1:0] div;
    reg [CNT_W-1:0] us_cnt;
    reg [11:0]      pulse_latched;
    wire us_tick = (div == TICKS_PER_US - 1);

    always @(posedge clk) begin
        if (rst) begin
            div <= 0; us_cnt <= 0; pulse_latched <= 0; servo_out <= 1'b0;
        end else begin
            div <= us_tick ? 0 : div + 1'b1;
            if (us_tick) begin
                if (us_cnt == FRAME_US - 1) begin
                    us_cnt        <= 0;
                    pulse_latched <= pulse_us;
                end else
                    us_cnt <= us_cnt + 1'b1;
            end
            servo_out <= (us_cnt < pulse_latched);
        end
    end
endmodule
