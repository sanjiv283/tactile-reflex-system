`timescale 1ns / 1ps
// MCP3008 SPI master: one single-ended conversion per request.
//
// SPI mode 0 (CPOL=0, CPHA=0): SCLK idles low; MOSI changes on the falling
// edge; the ADC latches MOSI and we sample MISO on the rising edge.
// Frame = 17 SCLK rising edges with CS low (MCP3008 datasheet, single-ended):
//   rise 1: start bit (1)   rise 2: SGL/DIFF = 1   rises 3-5: D2 D1 D0
//   rise 7: null bit (must read 0)   rises 8-17: B9 .. B0 (MSB first)
// Timing (all derived from CLK_HZ/SCLK_HZ; HALF = clocks per half SCLK period):
//   CS fall -> first rising edge     = HALF clocks  (datasheet tSUCS >= 100 ns)
//   CS high between conversions      >= HALF clocks (datasheet tCSH  >= 270 ns)
//   Start-to-start conversion period = 35*HALF + 1 clocks
// SCLK_HZ is capped at 1.35 MHz (datasheet limit at VDD = 2.7 V, so valid at 3.3 V).
//
// start  : level-sensitive request. Held high = continuous back-to-back conversions.
//          Ignored while busy, so conversions never overlap.
// channel: latched when a conversion starts.
// data_valid : 1-clock pulse with data/data_channel.
// frame_err  : 1-clock pulse instead of data_valid when the null bit reads 1
//              (e.g. MISO disconnected with the pin's pull-up enabled). Data is
//              not updated, so the safety governor's ADC timeout still applies.
// MISO goes through a 2-flop synchronizer before sampling.
module adc_spi_interface #(
    parameter CLK_HZ  = 100_000_000,
    parameter SCLK_HZ = 1_000_000
)(
    input  wire       clk,
    input  wire       rst,           // synchronous, active high (same as reflex_top)
    input  wire       start,
    input  wire [2:0] channel,
    output wire       busy,
    output reg  [9:0] data,
    output reg  [2:0] data_channel,
    output reg        data_valid,
    output reg        frame_err,
    output reg        spi_cs_n,
    output reg        spi_sclk,
    output wire       spi_mosi,
    input  wire       spi_miso
);
    // Round HALF up so the real SCLK is never faster than SCLK_HZ.
    localparam HALF = (CLK_HZ + 2*SCLK_HZ - 1) / (2*SCLK_HZ);
    localparam HW   = $clog2(HALF + 1);

    // Elaboration-time parameter check: an invalid setting refers to a module
    // that does not exist, so simulation and synthesis both stop with an error.
    //  - SCLK_HZ must be 10 kHz .. 1.35 MHz (datasheet range at 2.7-3.3 V)
    //  - HALF >= 8 leaves time for the MISO synchronizer + 200 ns tDO
    generate
        if (SCLK_HZ > 1_350_000 || SCLK_HZ < 10_000 || HALF < 8) begin : g_bad_params
            ADC_SPI_INTERFACE_invalid_CLK_HZ_or_SCLK_HZ u_param_check ();
        end
    endgenerate

    localparam S_IDLE = 2'd0, S_XFER = 2'd1, S_GAP = 2'd2;

    reg [1:0]    state;
    reg [HW-1:0] div;
    reg [4:0]    rises;        // rising edges done in this frame (0..17)
    reg [4:0]    tx;           // {start, SGL, D2, D1, D0}, MSB goes out first
    reg [10:0]   rx;           // {null, B9..B0} after 17 shifts
    reg [2:0]    ch_l;
    reg [1:0]    miso_s;

    wire tick = (div == HALF - 1);
    assign busy     = (state != S_IDLE);
    assign spi_mosi = tx[4];

    always @(posedge clk) begin
        miso_s     <= {miso_s[0], spi_miso};
        data_valid <= 1'b0;
        frame_err  <= 1'b0;
        if (rst) begin
            // Reset into GAP: CS stays high for at least HALF clocks after reset,
            // so an aborted frame always gets a proper CS-high time.
            state <= S_GAP; div <= 0; rises <= 0; tx <= 0; rx <= 0; ch_l <= 0;
            spi_cs_n <= 1'b1; spi_sclk <= 1'b0;
            data <= 0; data_channel <= 0;
        end else begin
            div <= (state == S_IDLE || tick) ? 0 : div + 1'b1;
            case (state)
                S_IDLE: if (start) begin
                    ch_l     <= channel;
                    tx       <= {2'b11, channel};
                    rises    <= 0;
                    spi_cs_n <= 1'b0;
                    state    <= S_XFER;
                end
                S_XFER: if (tick) begin
                    if (!spi_sclk) begin                    // rising edge
                        spi_sclk <= 1'b1;
                        rises    <= rises + 1'b1;
                        rx       <= {rx[9:0], miso_s[1]};
                    end else begin                          // falling edge
                        spi_sclk <= 1'b0;
                        if (rises == 5'd17) begin
                            spi_cs_n <= 1'b1;
                            state    <= S_GAP;
                            if (rx[10] == 1'b0) begin
                                data         <= rx[9:0];
                                data_channel <= ch_l;
                                data_valid   <= 1'b1;
                            end else
                                frame_err <= 1'b1;
                        end else
                            tx <= {tx[3:0], 1'b0};
                    end
                end
                S_GAP: if (tick) state <= S_IDLE;
                default: state <= S_GAP;
            endcase
        end
    end
endmodule
