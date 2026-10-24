// input_conditioning: registers the ADC sample and flags invalid readings.
// No averaging here on purpose: filtering would add latency to the reflex path.
module input_conditioning #(
    parameter [11:0] RAIL_HI = 12'hFF0   // readings at or above this are treated as invalid (shorted / railed)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] sample,
    input  wire        sample_valid,
    input  wire        frame_err,
    output reg  [11:0] force_code,
    output reg         force_valid,
    output reg         adc_invalid       // valid together with force_valid, held between samples
);
    always @(posedge clk) begin
        if (!rst_n) begin
            force_code <= 12'd0; force_valid <= 1'b0; adc_invalid <= 1'b0;
        end else begin
            force_valid <= sample_valid;
            if (sample_valid) begin
                force_code  <= sample;
                adc_invalid <= frame_err | (sample >= RAIL_HI);
            end
        end
    end
endmodule
