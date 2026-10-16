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

    // Elaboration-time parameter checks: an invalid setting refers to a module that does not exist,
    // so compilation fails with the module name below.
    generate
        // TICKS_PER_US is an integer division: a clock below 1 MHz gives 0 ticks (no pulses at all),
        // a clock that is not a whole number of MHz gives pulses of the wrong width.
        if (CLK_HZ < 1_000_000 || CLK_HZ % 1_000_000 != 0) begin : g_bad_clk
            SERVO_PWM_GENERATOR_invalid_CLK_HZ u_param_check ();
        end
        // INTEGRATION ASSUMPTION, not a limit of this module: pulse_us is a 12-bit input (up to 4095) and this
        // module does not know the pulse limits. The 2000 us here is the current safety_governor default
        // PULSE_MAX_US. The frame needs at least 1 us of low time after the longest pulse, so with
        // FRAME_US <= 2000 the output would stay high between 2000 us pulses. A governor with PULSE_MAX_US > 2000
        // needs a longer FRAME_US; no local guard can check that relationship across the two modules.
        if (FRAME_US <= 2000) begin : g_bad_frame
            SERVO_PWM_GENERATOR_invalid_FRAME_US u_param_check ();
        end
    endgenerate

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
