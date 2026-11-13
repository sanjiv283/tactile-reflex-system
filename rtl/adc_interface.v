// adc_interface: continuous SPI reader for an AD7476A-style 12-bit ADC (16 SCLK frame).
// SCLK idles high, MISO is sampled on the falling edge, frame = 4 leading zeros + 12 data bits.
// ponytail: format assumed from the AD7476A datasheet; confirm the bit alignment against the real part.
module adc_interface #(
    parameter CLK_DIV = 6,    // SCLK period in clk cycles (even); 50 MHz / 6 = 8.33 MHz (AD7476A max 20 MHz)
    parameter GAP     = 8,    // CS high time between frames, in clk cycles (1..256; >= 64 when IDLE_CHK=1 so a pull-up can settle; other values fail elaboration)
    // Idle-level check: with CS high the AD7476A releases MISO and a weak pull-up holds it high. MISO still low at the
    // end of the gap = line stuck low (or ADC driving low): the next frame is flagged via frame_err. A legitimate
    // reading of 0 is NOT rejected; only the line level while CS is high is looked at. Default off until the Pmod AD1
    // tri-state behaviour is confirmed on hardware.
    parameter IDLE_CHK = 0
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
    // Parameter guard (elaboration error, never a clamp). Valid: 1 <= GAP <= 256 (8-bit gap counter), and GAP >= 64 when IDLE_CHK != 0.
    // Verilog-2005 has no elaboration-time error task (Yosys 0.33 rejects $error), so an invalid setting instantiates a module that does
    // not exist: iverilog, Yosys, Verilator and Quartus all stop with "unknown module ERROR_adc_interface_...", which names the rule.
    generate
        if (GAP < 1 || GAP > 256 || (IDLE_CHK != 0 && GAP < 64)) begin : bad_gap_config
            ERROR_adc_interface_GAP_must_be_1_to_256_and_at_least_64_when_IDLE_CHK_is_1 invalid_parameters();
        end
    endgenerate
    localparam S_GAP = 1'b0, S_XFER = 1'b1;

    reg        st;
    reg [7:0]  cnt;
    reg [4:0]  bits;
    reg [15:0] sh;
    reg        idle_low;   // MISO low at the end of the CS-high gap (before this frame)

    always @(posedge clk) begin
        if (!rst_n) begin
            adc_cs_n <= 1'b1; adc_sclk <= 1'b1; st <= S_GAP; cnt <= 8'd0; bits <= 5'd0;
            sh <= 16'd0; sample <= 12'd0; sample_valid <= 1'b0; frame_err <= 1'b0; idle_low <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            case (st)
                S_GAP: begin
                    adc_cs_n <= 1'b1; adc_sclk <= 1'b1;
                    if (cnt == GAP - 1) begin
                        cnt <= 8'd0; adc_cs_n <= 1'b0; bits <= 5'd0; st <= S_XFER; idle_low <= ~adc_miso;
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
                                sample <= sh[11:0]; frame_err <= (sh[15:12] != 4'd0) || (IDLE_CHK != 0 && idle_low);
                                sample_valid <= 1'b1;
                            end
                        end
                    end else cnt <= cnt + 8'd1;
                end
            endcase
        end
    end
endmodule
