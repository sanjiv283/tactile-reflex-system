// Hobby-servo PWM: 1 us resolution, pulse width latched at the start of each frame.
// Output stays low while rst is high.
module servo_pwm_generator #(
    parameter CLK_HZ   = 100_000_000,   // must be a whole number of MHz
    parameter FRAME_US = 20000
) (
    input             clk,
    input             rst,
    input      [11:0] pulse_us,
    output reg        pwm
);
    localparam integer TICKDIV = CLK_HZ / 1_000_000;

    reg [15:0] sub;     // clocks within a microsecond
    reg [15:0] us;      // microseconds within the frame
    reg [11:0] pulse_l;

    always @(posedge clk) begin
        if (rst) begin
            sub <= 0; us <= 0; pulse_l <= pulse_us; pwm <= 0;
        end else begin
            pwm <= (us < pulse_l);
            if (sub == TICKDIV - 1) begin
                sub <= 0;
                if (us == FRAME_US - 1) begin
                    us <= 0;
                    pulse_l <= pulse_us;
                end else us <= us + 1;
            end else sub <= sub + 1;
        end
    end
endmodule
