`timescale 1ns / 1ps
// Characterisation of the stuck-low check against a SLOW MISO pull-up (rtl/adc_spi_interface.v samples MISO at SCLK
// rising edge 5, while the MCP3008 output is still high-impedance and only the pull-up holds the line high).
// Model: when the ADC releases the line (CS rising) the pulled-up level needs PULL_RISE_NS to reach the input-high level
// (a pure delay, NOT a real RC curve and NOT a measurement). The previous code's last bit is 0, the worst case, because
// the line then starts the next frame from low.
//   EXPECT_OK = 1: every frame must be accepted (pull-up fast enough)
//   EXPECT_OK = 0: frames after the first must be rejected as frame_err (pull-up too slow: safe direction, ADC timeout fault)
// At 50 MHz / 1 MHz SCLK edge 5 is 5020 ns after CS rose (measured in simulation), so the simulated limit is about 5.0 us.
module tb_miso_pullup_rise;
    parameter PULL_RISE_NS = 4000;
    parameter EXPECT_OK    = 1;
    reg clk = 0; always #10 clk = ~clk;                 // 50 MHz

    reg rst = 1, start = 0;
    wire busy, data_valid, frame_err, cs_n, sclk, mosi, adc_dout;
    wire [9:0] data; wire [2:0] data_channel;
    reg pull_hi = 1;                                    // pulled-up level as seen at the pin
    always @(adc_dout)
        if (adc_dout === 1'bz) begin #(PULL_RISE_NS); if (adc_dout === 1'bz) pull_hi = 1'b1; end
        else pull_hi = 1'b0;
    wire miso = (adc_dout === 1'bz) ? pull_hi : adc_dout;

    adc_spi_interface #(.CLK_HZ(50_000_000), .SCLK_HZ(1_000_000)) dut (
        .clk(clk), .rst(rst), .start(start), .channel(3'd0), .busy(busy), .data(data), .data_channel(data_channel),
        .data_valid(data_valid), .frame_err(frame_err), .spi_cs_n(cs_n), .spi_sclk(sclk), .spi_mosi(mosi), .spi_miso(miso));
    mcp3008_model u_adc (.cs_n(cs_n), .sclk(sclk), .din(mosi), .dout(adc_dout));

    integer errors = 0, nv = 0, ne = 0, i;
    task check(input cond, input [8*96-1:0] name);
        begin
            if (cond === 1'b1) $display("PASS  %0s", name);
            else begin $display("FAIL  %0s", name); errors = errors + 1; end
        end
    endtask
    always @(posedge clk) begin if (data_valid) nv = nv + 1; if (frame_err) ne = ne + 1; end
    task convert; begin
        start = 1; @(posedge busy); start = 0; @(negedge busy); repeat (4) @(posedge clk);
    end endtask

    initial begin
        u_adc.value[0] = 10'd512;                       // 1000000000: last data bit B0 = 0, so the line is low when the ADC releases it
        #100 rst = 0; #100;
        convert;                                        // warm-up frame: the line starts high, so this one is not representative
        nv = 0; ne = 0;
        for (i = 0; i < 3; i = i + 1) convert;
        $display("INFO  pull-up rise time %0d ns: %0d valid, %0d frame_err of 3 frames", PULL_RISE_NS, nv, ne);
        if (EXPECT_OK) check(nv == 3 && ne == 0, "pull-up rise time within the margin: all frames accepted");
        else           check(nv == 0 && ne == 3, "pull-up too slow (beyond edge 5): frames rejected, safe direction");
        $display("=== DONE: %0d error(s) ===", errors);
        $finish;
    end
    initial begin #2_000_000; $display("FAIL  watchdog"); $display("=== DONE: watchdog ==="); $finish; end
endmodule
