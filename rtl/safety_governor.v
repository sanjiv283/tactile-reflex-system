// safety_governor: hard limits enforced in hardware. The AI class can only LOWER the command,
// and is ignored entirely when invalid or when any hard limit trips.
module safety_governor #(
    parameter [11:0] FORCE_MAX = 12'hA00,  // trip threshold
    parameter [11:0] FORCE_REL = 12'h900,  // release threshold (hysteresis)
    parameter [7:0]  HOLD_CAP  = 8'd64,    // command cap when AI says class 2 (normal grip)
    parameter [7:0]  EXCESS_CAP= 8'd24     // command cap when AI says class 3 (excessive force)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,       // lut_valid: new force_code / lut_cmd pair
    input  wire [11:0] force_code,
    input  wire [7:0]  lut_cmd,
    input  wire        adc_invalid,
    input  wire        sensor_fault,
    input  wire        estop_active,
    input  wire        ai_valid,
    input  wire [1:0]  ai_class,
    output reg  [7:0]  cmd_out,
    output reg         safe_state,     // also gates the PWM output directly
    output reg  [3:0]  trip_reason,    // [0] force max, [1] sensor fault, [2] e-stop, [3] invalid ADC
    output reg         ai_used,
    output reg         ai_overridden   // hard limit tripped while the AI did not predict excess force
);
    reg armed;        // stays in safe state until the first valid sample after reset
    reg force_over;

    reg        force_over_n;
    reg        trip;
    reg [7:0]  ai_cmd;

    always @(posedge clk) begin
        if (!rst_n) begin
            armed <= 1'b0; force_over <= 1'b0; cmd_out <= 8'd0; safe_state <= 1'b1;
            trip_reason <= 4'd0; ai_used <= 1'b0; ai_overridden <= 1'b0;
        end else begin
            if (in_valid) armed <= 1'b1;

            force_over_n = force_over;
            if (in_valid) begin
                if (force_code >= FORCE_MAX)      force_over_n = 1'b1;
                else if (force_code < FORCE_REL)  force_over_n = 1'b0;
            end
            force_over <= force_over_n;

            trip = force_over_n | sensor_fault | estop_active | adc_invalid | ~armed;

            ai_cmd = lut_cmd;
            if (ai_valid) begin
                case (ai_class)
                    2'd2: ai_cmd = (lut_cmd < HOLD_CAP)   ? lut_cmd : HOLD_CAP;
                    2'd3: ai_cmd = (lut_cmd < EXCESS_CAP) ? lut_cmd : EXCESS_CAP;
                    default: ai_cmd = lut_cmd;
                endcase
            end

            cmd_out       <= trip ? 8'd0 : ai_cmd;
            safe_state    <= trip;
            trip_reason   <= {adc_invalid, estop_active, sensor_fault, force_over_n};
            ai_used       <= ai_valid & ~trip;
            ai_overridden <= trip & ai_valid & (ai_class != 2'd3);
        end
    end
endmodule
