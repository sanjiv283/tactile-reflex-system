// input_conditioning: registers the ADC sample and flags invalid readings.
// No averaging here on purpose: filtering would add latency to the reflex path.
module input_conditioning #(
    parameter [11:0] RAIL_HI = 12'hFF0,  // readings at or above this are treated as invalid (shorted / railed)
    // Advisory only: zero_run goes high after ZERO_FRAMES consecutive valid frames reading exactly 0 (0 disables).
    // A zero reading is legitimate (no contact); this flag never trips anything, it only tells the operator.
    parameter        ZERO_FRAMES = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] sample,
    input  wire        sample_valid,
    input  wire        frame_err,
    output reg  [11:0] force_code,
    output reg         force_valid,
    output reg         adc_invalid,      // valid together with force_valid, held between samples
    output reg         zero_run          // advisory: long run of exact-zero readings, no safety action
);
    reg [31:0] zcnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            force_code <= 12'd0; force_valid <= 1'b0; adc_invalid <= 1'b0; zcnt <= 32'd0; zero_run <= 1'b0;
        end else begin
            force_valid <= sample_valid;
            if (sample_valid) begin
                if (sample == 12'd0 && !frame_err) begin
                    if (zcnt < ZERO_FRAMES) zcnt <= zcnt + 32'd1;
                end else zcnt <= 32'd0;
                zero_run <= (ZERO_FRAMES != 0) && (sample == 12'd0) && !frame_err && (zcnt >= ZERO_FRAMES - 1);
            end
            if (sample_valid) begin
                force_code  <= sample;
                adc_invalid <= frame_err | (sample >= RAIL_HI);
            end
        end
    end
endmodule
