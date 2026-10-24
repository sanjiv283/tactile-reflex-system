// adc_interface: continuous SPI reader for an AD7476A-style 12-bit ADC (16 SCLK frame).
// SCLK idles high, MISO is sampled on the falling edge, frame = 4 leading zeros + 12 data bits.
// ponytail: format assumed from the AD7476A datasheet; confirm the bit alignment against the real part.
module adc_interface #(
    parameter CLK_DIV = 10,   // SCLK period in clk cycles (even); 100 MHz / 10 = 10 MHz
    parameter GAP     = 8     // CS high time between frames, in clk cycles
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        adc_miso,
    output reg         adc_cs_n,
    output reg         adc_sclk,
    output reg  [11:0] sample,
    output reg         sample_valid,  // 1-cycle pulse, sample is stable from this cycle on
    output reg         frame_err      // leading zeros were not zero
);
    localparam HALF  = CLK_DIV / 2;
    localparam S_GAP = 1'b0, S_XFER = 1'b1;

    reg        st;
    reg [7:0]  cnt;
    reg [4:0]  bits;
    reg [15:0] sh;

    always @(posedge clk) begin
        if (!rst_n) begin
            adc_cs_n <= 1'b1; adc_sclk <= 1'b1; st <= S_GAP; cnt <= 8'd0; bits <= 5'd0;
            sh <= 16'd0; sample <= 12'd0; sample_valid <= 1'b0; frame_err <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            case (st)
                S_GAP: begin
                    adc_cs_n <= 1'b1; adc_sclk <= 1'b1;
                    if (cnt == GAP - 1) begin
                        cnt <= 8'd0; adc_cs_n <= 1'b0; bits <= 5'd0; st <= S_XFER;
                    end else cnt <= cnt + 8'd1;
                end
                S_XFER: begin
                    if (cnt == HALF - 1) begin
                        cnt <= 8'd0;
                        if (adc_sclk) begin                 // falling edge: sample MISO
                            adc_sclk <= 1'b0;
                            sh       <= {sh[14:0], adc_miso};
                            bits     <= bits + 5'd1;
                        end else begin                      // rising edge
                            adc_sclk <= 1'b1;
                            if (bits == 5'd16) begin
                                st <= S_GAP; adc_cs_n <= 1'b1;
                                sample <= sh[11:0]; frame_err <= (sh[15:12] != 4'd0);
                                sample_valid <= 1'b1;
                            end
                        end
                    end else cnt <= cnt + 8'd1;
                end
            endcase
        end
    end
endmodule
