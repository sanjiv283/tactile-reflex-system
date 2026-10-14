// MCP3008 SPI master, single-ended, mode 0. One conversion per accepted `start`.
// 17 SCLK rising edges: start, SGL=1, D2..D0, sample clock, null bit, B9..B0.
// data/data_valid: data_valid is a 1-clock pulse, registered on the same edge CS rises.
// frame_err (1-clock pulse): null bit was 1 (e.g. MISO disconnected + pull-up); data not updated.
// busy is high in every state except idle; start is ignored while busy.
// After reset CS stays high for >= half an SCLK period.
module adc_spi_interface #(
    parameter CLK_HZ  = 100_000_000,
    parameter SCLK_HZ = 1_000_000          // 10 kHz .. 1.35 MHz, CLK_HZ >= 16*SCLK_HZ
) (
    input            clk,
    input            rst,                  // synchronous, active high
    input            start,
    input      [2:0] channel,              // latched when the conversion is accepted
    input            miso,
    output reg       cs_n,
    output reg       sclk,
    output reg       mosi,
    output           busy,
    output reg [9:0] data,
    output reg       data_valid,
    output reg       frame_err
);
    generate if (SCLK_HZ < 10_000 || SCLK_HZ > 1_350_000 || CLK_HZ < 16 * SCLK_HZ) begin : bad_param
        adc_spi_interface_parameter_out_of_range u_err();
    end endgenerate

    // rounded up so SCLK never exceeds SCLK_HZ
    localparam integer HALF = (CLK_HZ + 2 * SCLK_HZ - 1) / (2 * SCLK_HZ);

    localparam [2:0] S_IDLE = 0, S_SETUP = 1, S_HIGH = 2, S_LOW = 3, S_GAP = 4;

    reg [2:0]  st;
    reg [31:0] div;
    reg [4:0]  nrise;
    reg [16:0] tx;
    reg [10:0] rx;                         // {null, B9..B0}
    reg        m1, ms;                     // 2-flop MISO synchronizer

    assign busy = (st != S_IDLE);

    always @(posedge clk) begin
        m1 <= miso; ms <= m1;
        data_valid <= 0;
        frame_err  <= 0;
        if (rst) begin
            st <= S_GAP; div <= 0; nrise <= 0; tx <= 0; rx <= 0;
            cs_n <= 1; sclk <= 0; mosi <= 0; data <= 0;
        end else case (st)
            S_IDLE: if (start) begin
                cs_n <= 0; mosi <= 1; tx <= {2'b11, channel, 12'b0};
                div <= 0; nrise <= 0; st <= S_SETUP;
            end
            S_SETUP: if (div == HALF - 1) begin     // CS setup before first rising edge
                div <= 0; sclk <= 1; nrise <= 1; st <= S_HIGH;
            end else div <= div + 1;
            S_HIGH: if (div == HALF - 1) begin
                div <= 0;
                if (nrise == 17) begin               // frame done: CS rises with sclk low
                    sclk <= 0; cs_n <= 1; mosi <= 0; st <= S_GAP;
                    if (rx[10]) frame_err <= 1;
                    else begin data <= rx[9:0]; data_valid <= 1; end
                end else begin                       // falling edge: next MOSI bit
                    sclk <= 0; tx <= tx << 1; mosi <= tx[15]; st <= S_LOW;
                end
            end else div <= div + 1;
            S_LOW: if (div == HALF - 1) begin
                div <= 0; sclk <= 1; nrise <= nrise + 1; st <= S_HIGH;
                if (nrise + 1 >= 7) rx <= {rx[9:0], ms};   // null bit at edge 7, B0 at edge 17
            end else div <= div + 1;
            S_GAP: if (div == HALF - 1) st <= S_IDLE;      // CS-high time >= half period
                   else div <= div + 1;
            default: st <= S_GAP;
        endcase
    end
endmodule
