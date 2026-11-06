`timescale 1ns/1ps
// DE2-115 board wrapper: keys, UART AI packets in, UART telemetry out, e-stop paths, override with a hostile AI.
module tb_de2_115_top;
    reg clk = 0; always #10 clk = ~clk;
    localparam CPB = 16;
    reg [3:0] key = 4'b1111; reg uart_rxd = 1; reg estop_ext_n = 1; reg [11:0] value = 12'h000;
    wire [17:0] ledr; wire [8:0] ledg; wire uart_txd, cs_n, sclk, miso, pwm, dsv, dsafe;
    ad7476_model adc (.cs_n(cs_n), .sclk(sclk), .value(value), .corrupt(1'b0), .miso(miso));
    de2_115_top #(.CLKS_PER_BIT(CPB), .TX_PERIOD(3000), .AI_TIMEOUT(20000), .PRED_EN(0), .DEBOUNCE_CLKS(4)) dut (.CLOCK_50(clk), .KEY(key), .LEDR(ledr), .LEDG(ledg),
        .UART_RXD(uart_rxd), .UART_TXD(uart_txd), .ADC_CS_N(cs_n), .ADC_SCLK(sclk), .ADC_MISO(miso), .ESTOP_EXT_N(estop_ext_n),
        .PWM_OUT(pwm), .DBG_SAMPLE_VALID(dsv), .DBG_SAFE_STATE(dsafe));
    wire safe = ledr[0], sfault = ledr[1], estop = ledr[2], aiov = ledr[3], aiv = ledg[0];

    reg [7:0] rom [0:255]; initial $readmemh("rtl/force_lut.mem", rom);
    integer pass = 0, fail = 0;
    safety_monitor #(.NAME("de2")) smon (.clk(clk), .rst_s(dut.u_core.rst_s), .safe_state(dut.u_core.safe_state), .pwm_out(dut.u_core.pwm_out), .cmd_out(dut.u_core.cmd_out), .lut_cmd(dut.u_core.lut_cmd),
        .lut_valid(dut.u_core.lut_valid), .lut_force(dut.u_core.lut_force), .estop_active(dut.u_core.estop_active), .sensor_fault(dut.u_core.sensor_fault), .adc_invalid(dut.u_core.adc_invalid));
    task check(input c, input [383:0] msg); begin if (c) pass = pass + 1; else begin fail = fail + 1; $display("FAIL @%0t: %0s", $time, msg); end end endtask
    task frames(input integer n); integer i; begin for (i = 0; i < n; i = i + 1) begin @(posedge clk); while (!dsv) @(posedge clk); end end endtask
    task settle; begin frames(4); repeat (10) @(posedge clk); end endtask
    task press_clear; begin key[1] = 0; repeat (10) @(posedge clk); key[1] = 1; repeat (6) @(posedge clk); end endtask
    task tx_byte(input [7:0] b); integer k; begin uart_rxd = 0; repeat (CPB) @(posedge clk); for (k = 0; k < 8; k = k + 1) begin uart_rxd = b[k]; repeat (CPB) @(posedge clk); end uart_rxd = 1; repeat (CPB) @(posedge clk); end endtask
    // AI packet sender: class 0..3 (data = {3'b0, valid, ~cls, cls}, chk = ~data)
    reg [1:0] cls = 0; reg run = 0; reg bad = 0; reg [7:0] d;
    always begin
        wait (run); d = {3'b000, 1'b1, ~cls, cls}; tx_byte(8'hA5); tx_byte(d); tx_byte(bad ? d : ~d); repeat (2000) @(posedge clk);
    end
    // telemetry monitor
    wire [7:0] mb; wire mv; uart_rx #(.CLKS_PER_BIT(CPB)) mon (.clk(clk), .rst_n(key[3]), .rxd(uart_txd), .data(mb), .valid(mv));
    reg [1:0] mi = 0; reg [7:0] m1, m2; integer tele_ok = 0, tele_bad = 0; reg [11:0] last_force; reg [3:0] last_flags;
    always @(posedge clk) if (mv) begin
        case (mi) 0: mi <= (mb == 8'h5A) ? 1 : 0; 1: begin m1 <= mb; mi <= 2; end
            2: begin m2 <= mb; mi <= 0; last_force <= {m1[3:0], mb}; last_flags <= m1[7:4]; tele_ok <= tele_ok + 1; end endcase
    end

    integer h, n;
    initial begin
        key[3] = 0; repeat (6) @(posedge clk); #1 check(pwm === 1'b0 && safe === 1'b1, "reset (KEY3): PWM low, safe state");
        key[3] = 1; frames(3); press_clear; settle; check(safe === 1'b0 && estop === 1'b0, "KEY1 clear after reset releases the safe state");
        check(aiv === 1'b0, "no AI packets yet: AI not valid");
        value = 12'h400; settle; check(dut.u_core.cmd_out === rom[12'h400 >> 4], "FPGA-only: LUT command without AI");
        cls = 2; run = 1; repeat (9000) @(posedge clk); settle;
        check(aiv === 1'b1 && dut.u_core.cmd_out === 8'd64, "AI class 2 over UART: command capped at 64");
        cls = 3; repeat (6000) @(posedge clk); settle; check(dut.u_core.cmd_out === 8'd24, "AI class 3 over UART: command capped at 24");
        cls = 2; repeat (6000) @(posedge clk); settle;
        value = 12'hB00; settle; check(safe === 1'b1 && pwm === 1'b0 && aiov === 1'b1, "excess force with AI 'normal grip': safe state, override flagged");
        value = 12'h400; settle; check(safe === 1'b0, "force back to normal: released");
        // telemetry matches the ADC value
        repeat (9000) @(posedge clk); check(tele_ok > 3 && last_force === 12'h400, "telemetry carries the force code");
        // e-stop: onboard key and external contact
        cls = 0; repeat (6000) @(posedge clk); @(posedge pwm);
        key[0] = 0; repeat (8) @(posedge clk); #1 check(pwm === 1'b0 && safe === 1'b1 && estop === 1'b1, "KEY0 e-stop: PWM low, latched");
        key[0] = 1; settle; check(safe === 1'b1, "latched after release"); press_clear; settle; check(safe === 1'b0, "KEY1 clears");
        @(posedge pwm); estop_ext_n = 0; repeat (8) @(posedge clk); #1 check(pwm === 1'b0 && safe === 1'b1, "external NC e-stop opens: stop");
        estop_ext_n = 1; settle; press_clear; settle; check(safe === 1'b0, "external e-stop released and cleared");
        // AI link failure: corrupt checksums only
        bad = 1; cls = 2; repeat (30000) @(posedge clk); settle; check(aiv === 1'b0 && dut.u_core.cmd_out === rom[12'h400 >> 4], "corrupt AI packets: AI ignored, FPGA-only command");
        bad = 0; repeat (9000) @(posedge clk); settle; check(aiv === 1'b1, "good packets again: AI valid");
        run = 0; repeat (30000) @(posedge clk); settle; check(aiv === 1'b0, "AI packets stop: AI ignored");
        value = 12'hB00; settle; check(safe === 1'b1, "excess force with no AI: safe state");
        // wrapper-level reset synchroniser, seen at the UART/AI bridge and at the release timing
        tx_byte(8'hA5); tx_byte(8'h16); @(negedge clk); #4 key[3] = 0; #3 key[3] = 1; repeat (6) @(posedge clk); tx_byte(8'hE9);
        check(dut.u_bridge.ai_gpio === 16'h0000, "3 ns reset pulse clears a half-received AI packet (the complement byte alone must not complete it)");
        @(negedge clk); key[3] = 0; repeat (3) @(posedge clk); @(negedge clk); key[3] = 1; #1 check(dut.rst_n === 1'b0, "KEY3 released: wrapper reset still asserted at once");
        @(posedge clk); #1 check(dut.rst_n === 1'b0, "wrapper reset still asserted one clock after KEY3 release (two-stage synchroniser)");
        @(posedge clk); #1 check(dut.rst_n === 1'b1, "wrapper reset released two clocks after KEY3 release");
        check(smon.viol == 0, "safety_monitor: no invariant violation in any scenario"); $display("TB tb_de2_115_top: PASS %0d FAIL %0d VECTORS 0 NOTE directed board-wrapper scenarios; DEBOUNCE_CLKS=4", pass, fail); $finish;
    end
    initial begin #100_000_000; $display("TB tb_de2_115_top: TIMEOUT"); $finish; end
endmodule
