// pwm_generator: 12-bit free-running counter (50 MHz / 4096 = 12.2 kHz), 8-bit duty.
// Duty changes take effect at the period boundary; `kill` forces the output low on the next clock.
module pwm_generator (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] duty,
    input  wire       kill,
    output reg        pwm_out
);
    reg [11:0] cnt;
    reg [7:0]  duty_active;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 12'd0; duty_active <= 8'd0; pwm_out <= 1'b0;
        end else begin
            cnt <= cnt + 12'd1;
            if (cnt == 12'hFFF) duty_active <= duty;
            pwm_out <= (cnt[11:4] < duty_active) & ~kill;
        end
    end
endmodule
