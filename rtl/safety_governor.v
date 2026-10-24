// safety_governor: hard limits enforced in hardware. The AI class can only LOWER the command,
// and is ignored entirely when invalid or when any hard limit trips.
module safety_governor #(
    parameter [11:0] FORCE_MAX = 12'hA00,  // trip threshold
    parameter [11:0] FORCE_REL = 12'h900,  // release threshold (hysteresis)
    parameter [7:0]  HOLD_CAP  = 8'd64,    // command cap when AI says class 2 (normal grip)
    parameter [7:0]  EXCESS_CAP= 8'd24,    // command cap when AI says class 3 (excessive force)
    // slope-predictive pre-limit (fixed-function, no ML): force + PRED_K * (rise per window) >= FORCE_MAX
    parameter        PRED_EN   = 1,
    parameter        PRED_WIN  = 150000,   // window in clocks (3 ms at 50 MHz)
    parameter        PRED_K    = 2,        // look-ahead in windows
    parameter [11:0] PRED_MIN_DELTA = 12'd150  // minimum rise per window that counts as a real ramp (noise guard)
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
    output reg  [4:0]  trip_reason,    // [0] force max, [1] sensor fault, [2] e-stop, [3] invalid ADC, [4] predicted over-force
    output reg         ai_used,
    output reg         ai_overridden   // hard limit tripped while the AI did not predict excess force
);
    reg armed;        // stays in safe state until the first valid sample after reset
    reg force_over;

    reg        force_over_n;
    reg        trip;
    reg        pred_trip;

    // slope predictor: snapshot the force every PRED_WIN clocks, delta = rise over the last window
    reg [31:0] wcnt;
    reg [11:0] snap;
    reg signed [12:0] delta;
    reg        seeded;
    integer    pv;
    reg [7:0]  ai_cmd;

    always @(posedge clk) begin
        if (!rst_n) begin
            armed <= 1'b0; force_over <= 1'b0; cmd_out <= 8'd0; safe_state <= 1'b1;
            trip_reason <= 5'd0; ai_used <= 1'b0; ai_overridden <= 1'b0;
            wcnt <= 32'd0; snap <= 12'd0; delta <= 13'sd0; seeded <= 1'b0;
        end else begin
            if (wcnt >= PRED_WIN - 1) begin
                wcnt <= 32'd0; snap <= force_code;
                delta <= seeded ? ($signed({1'b0, force_code}) - $signed({1'b0, snap})) : 13'sd0;
                seeded <= 1'b1;
            end else wcnt <= wcnt + 32'd1;

            if (in_valid) armed <= 1'b1;

            force_over_n = force_over;
            if (in_valid) begin
                if (force_code >= FORCE_MAX)      force_over_n = 1'b1;
                else if (force_code < FORCE_REL)  force_over_n = 1'b0;
            end
            force_over <= force_over_n;

            pv = $signed({1'b0, force_code}) + PRED_K * delta;
            pred_trip = (PRED_EN != 0) && (delta >= $signed({1'b0, PRED_MIN_DELTA})) && (pv >= FORCE_MAX);

            trip = force_over_n | sensor_fault | estop_active | adc_invalid | ~armed | pred_trip;

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
            trip_reason   <= {pred_trip, adc_invalid, estop_active, sensor_fault, force_over_n};
            ai_used       <= ai_valid & ~trip;
            ai_overridden <= trip & ai_valid & (ai_class != 2'd3);
        end
    end
endmodule
