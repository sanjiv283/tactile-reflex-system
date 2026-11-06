`timescale 1ns/1ps
// Host-in-the-loop co-simulation harness (driven by tools/cosim_host_rtl.py). de2_115_top with a real UART at CPB=16.
//   +TRACE=<hex file, one 16-bit control word per step: [11:0] ADC value, [12] e-stop key pressed, [13] ADC frame error (corrupt), [14] operator clear press>
//   +N=<steps>  +STEP=<clocks per step>  +OUT=<telemetry hex out>  +LOG=<log out>  +AI=<hex file of AI bytes, 3 per telemetry frame>  +NAI=<byte count>
// Telemetry bytes received from UART_TXD are written to OUT, one frame (3 bytes) per line. AI packet k is sent after telemetry frame k+2 has been received
// (the host parser needs the next header to confirm a frame, so it answers one frame late). One log line per telemetry frame, written when the frame is complete:
//   frame,value,age,safe,ai_valid,cmd,pwm,sensor_fault,estop_key,estop_latch,ai_class,corrupt,step
// `age` = clocks since ANY control input (value, e-stop key, corrupt, clear key) last changed, so the tool only asserts on settled frames.
module cosim_harness;
    reg clk = 0; always #10 clk = ~clk;
    localparam CPB = 16;
    reg [3:0] key = 4'b1111; reg [11:0] value = 12'h000; reg corrupt = 0;
    wire [17:0] ledr; wire [8:0] ledg; wire txd, cs_n, sclk, miso, pwm, dsv, dsafe; wire rxd;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(corrupt), .miso(miso));
    reg [7:0] ab; reg asend = 0; wire abusy; uart_tx #(.CLKS_PER_BIT(CPB)) atx (.clk(clk), .rst_n(key[3]), .data(ab), .send(asend), .busy(abusy), .txd(rxd));
    de2_115_top #(.CLKS_PER_BIT(CPB), .TX_PERIOD(4000), .AI_TIMEOUT(40000), .PRED_EN(0), .DEBOUNCE_CLKS(4)) dut (.CLOCK_50(clk), .KEY(key), .LEDR(ledr), .LEDG(ledg),
        .UART_RXD(rxd), .UART_TXD(txd), .ADC_CS_N(cs_n), .ADC_SCLK(sclk), .ADC_MISO(miso), .ESTOP_EXT_N(1'b1), .PWM_OUT(pwm), .DBG_SAMPLE_VALID(dsv), .DBG_SAFE_STATE(dsafe));
    safety_monitor #(.NAME("cosim")) smon (.clk(clk), .rst_s(dut.u_core.rst_s), .safe_state(dut.u_core.safe_state), .pwm_out(dut.u_core.pwm_out), .cmd_out(dut.u_core.cmd_out), .lut_cmd(dut.u_core.lut_cmd),
        .lut_valid(dut.u_core.lut_valid), .lut_force(dut.u_core.lut_force), .estop_active(dut.u_core.estop_active), .sensor_fault(dut.u_core.sensor_fault), .adc_invalid(dut.u_core.adc_invalid));
    wire [7:0] tb_; wire tv; uart_rx #(.CLKS_PER_BIT(CPB)) trx (.clk(clk), .rst_n(key[3]), .rxd(txd), .data(tb_), .valid(tv));
    reg [15:0] trace [0:4095]; reg [7:0] aib [0:3*4096]; reg [2047:0] sTRACE, sOUT, sLOG, sAI; integer NAI, N, STEP, fo, fl, i = 0, frames = 0, nb = 0, sent = 0, age = 0, haveai = 0;
    reg [7:0] b0, b1, b2; reg [15:0] lastc = 0; event frame_ev;
    wire [15:0] ctrl = {key[1], key[0], corrupt, 1'b0, value};
    always @(posedge clk) begin age <= (ctrl == lastc) ? age + 1 : 0; lastc <= ctrl; end
    always @(posedge clk) if (tv) begin
        if (nb == 0) b0 = tb_; else if (nb == 1) b1 = tb_; else b2 = tb_;
        nb = nb + 1;
        if (nb == 3) begin nb = 0; frames = frames + 1; $fdisplay(fo, "%02x%02x%02x", b0, b1, b2);
            $fdisplay(fl, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d", frames, value, age, dut.u_core.safe_state, dut.u_core.ai_valid, dut.u_core.cmd_out, pwm, dut.u_core.sensor_fault, !key[0],
                      dut.u_core.estop_active, dut.u_core.ai_class, corrupt, i); -> frame_ev; end
    end
    always @(frame_ev) if (haveai && frames >= 2 && 3 * (sent + 1) <= NAI) begin : sender
        integer k;
        for (k = 0; k < 3; k = k + 1) begin @(negedge clk); while (abusy) @(negedge clk); ab = aib[3*sent + k]; asend = 1; @(negedge clk); asend = 0; end
        sent = sent + 1;
    end
    initial begin
        if (!$value$plusargs("N=%d", N) || !$value$plusargs("STEP=%d", STEP) || !$value$plusargs("TRACE=%s", sTRACE) || !$value$plusargs("OUT=%s", sOUT) || !$value$plusargs("LOG=%s", sLOG)) begin $display("ERROR missing plusargs"); $finish; end
        haveai = $value$plusargs("AI=%s", sAI); if (!$value$plusargs("NAI=%d", NAI)) NAI = 0; if (haveai) $readmemh(sAI, aib, 0, NAI - 1);
        $readmemh(sTRACE, trace, 0, N - 1); fo = $fopen(sOUT, "w"); fl = $fopen(sLOG, "w");
        key[3] = 0; repeat (6) @(posedge clk); key[3] = 1; repeat (3000) @(posedge clk);
        key[1] = 0; repeat (40) @(posedge clk); key[1] = 1; repeat (3000) @(posedge clk);                     // operator clear after power-up
        for (i = 0; i < N; i = i + 1) begin
            value = trace[i][11:0]; key[0] = !trace[i][12]; corrupt = trace[i][13];
            if (trace[i][14]) begin key[1] = 0; repeat (40) @(posedge clk); key[1] = 1; repeat (STEP - 40) @(posedge clk); end   // deliberate clear press at the start of the step
            else repeat (STEP) @(posedge clk);
        end
        $fclose(fo); $fclose(fl);
        $display("TB cosim_harness: PASS %0d FAIL %0d VECTORS %0d NOTE host-in-the-loop harness; real checks are in tools/cosim_host_rtl.py", (frames > 0 && smon.viol == 0) ? 1 : 0, (frames > 0 && smon.viol == 0) ? 0 : 1, frames);
        $finish;
    end
    initial begin #900_000_000; $display("TB cosim_harness: TIMEOUT"); $finish; end
endmodule
