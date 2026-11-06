#!/usr/bin/env python3
"""Mutation testing for the RTL regression: inject one deliberate bug at a time into a COPY of the repository and check that the
regression (tools/run_regression.py) fails. A mutant that survives means the tests cannot detect that class of bug.
Nothing in the working tree is modified. Usage: python3 tools/mutation_test.py [--only M23,M27] [--jobs 4] [--json results/mutation_report.json]
Statuses: KILLED (regression failed), SURVIVED (regression still passed: a test gap, or an equivalent mutant), INVALID (pattern not found / compile error).
Equivalent-mutant analysis for survivors must be written down in docs/VERIFICATION_REPORT.md."""
import argparse, json, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = [
 ("M01", "force limit uses > instead of >=", "rtl/safety_governor.v", "if (force_code >= FORCE_MAX)", "if (force_code > FORCE_MAX)"),
 ("M02", "hysteresis removed (release at FORCE_MAX)", "rtl/safety_governor.v", "else if (force_code < FORCE_REL)", "else if (force_code < FORCE_MAX)"),
 ("M03", "e-stop not a trip cause", "rtl/safety_governor.v", "| sensor_fault | estop_active | adc_invalid |", "| sensor_fault | 1'b0 | adc_invalid |"),
 ("M04", "sensor fault not a trip cause", "rtl/safety_governor.v", "force_over_n | sensor_fault | estop_active", "force_over_n | 1'b0 | estop_active"),
 ("M05", "invalid ADC not a trip cause", "rtl/safety_governor.v", "estop_active | adc_invalid | ~armed", "estop_active | 1'b0 | ~armed"),
 ("M06", "'not armed' wait removed", "rtl/safety_governor.v", "adc_invalid | ~armed | pred_trip", "adc_invalid | 1'b0 | pred_trip"),
 ("M07", "predictive trip ignored", "rtl/safety_governor.v", "~armed | pred_trip;", "~armed | 1'b0;"),
 ("M08", "AI class-2 cap removed", "rtl/safety_governor.v", "2'd2: ai_cmd = (lut_cmd < HOLD_CAP)   ? lut_cmd : HOLD_CAP;", "2'd2: ai_cmd = lut_cmd;"),
 ("M09", "AI class-3 uses wrong cap", "rtl/safety_governor.v", "(lut_cmd < EXCESS_CAP) ? lut_cmd : EXCESS_CAP;", "(lut_cmd < EXCESS_CAP) ? lut_cmd : HOLD_CAP;"),
 ("M10", "command not zeroed on trip", "rtl/safety_governor.v", "cmd_out       <= trip ? 8'd0 : ai_cmd;", "cmd_out       <= ai_cmd;"),
 ("M11", "override flag ignores class 3", "rtl/safety_governor.v", "ai_overridden <= trip & ai_valid & (ai_class != 2'd3);", "ai_overridden <= trip & ai_valid;"),
 ("M12", "predictor look-ahead K ignored", "rtl/safety_governor.v", "+ PRED_K * delta;", "+ delta;"),
 ("M13", "PWM kill removed", "rtl/pwm_generator.v", "& ~kill;", ";"),
 ("M14", "invalid-sample limit off by one", "rtl/fault_handler.v", "wire persist = (bad_cnt >= INVALID_LIMIT);", "wire persist = (bad_cnt > INVALID_LIMIT);"),
 ("M15", "ADC watchdog disabled", "rtl/fault_handler.v", "wire timeout = (wd_cnt >= WD_CYCLES);", "wire timeout = 1'b0;"),
 ("M16", "sensor fault can never be cleared", "rtl/fault_handler.v", "else if (fault_clear)   sensor_fault <= 1'b0;", "else if (1'b0)   sensor_fault <= 1'b0;"),
 ("M17", "railed-ADC threshold off by one", "rtl/input_conditioning.v", "(sample >= RAIL_HI)", "(sample > RAIL_HI)"),
 ("M18", "frame error never flagged", "rtl/adc_interface.v", "frame_err <= (sh[15:12] != 4'd0);", "frame_err <= 1'b0;"),
 ("M19", "AI integrity check disabled", "rtl/ai_control_interface.v", "wire integrity = (g2[5:4] == ~g2[1:0]);", "wire integrity = 1'b1;"),
 ("M20", "AI heartbeat timeout disabled", "rtl/ai_control_interface.v", "wire alive     = (tcnt < TIMEOUT);", "wire alive     = 1'b1;"),
 ("M21", "LUT index uses wrong bits", "rtl/force_lut.v", "rom[force_code[11:4]]", "rom[force_code[10:3]]"),
 ("M22", "e-stop reads 'released' during reset", "rtl/tactile_reflex_top.v", "begin es <= 2'b00; fc <= 2'b00; end", "begin es <= 2'b11; fc <= 2'b00; end"),
 ("M23", "UART stop bit not checked", "rtl/uart_rx.v", "if (rx) begin data <= sh; valid <= 1'b1; end\n                          else begin wait_idle <= 1'b1; cnt <= 16'd0; end", "begin data <= sh; valid <= 1'b1; end\n                          "),
 ("M24", "AI packet checksum ignored", "rtl/ai_uart_bridge.v", "if (rb == ~d) begin", "if (1'b1) begin"),
 ("M25", "telemetry header byte changed", "rtl/telemetry_tx.v", "8'h5A", "8'h5B"),
 ("M26", "fault-clear button polarity inverted", "rtl/de2_115_top.v", ".ACTIVE_LOW(1)) u_clr", ".ACTIVE_LOW(0)) u_clr"),
 ("M27", "UART rx does not wait for idle after a framing error", "rtl/uart_rx.v", "else begin wait_idle <= 1'b1; cnt <= 16'd0; end", "else begin wait_idle <= 1'b0; cnt <= 16'd0; end"),
 ("M28", "UART rx does not wait for idle after reset", "rtl/uart_rx.v", "valid <= 1'b0; wait_idle <= 1'b1;", "valid <= 1'b0; wait_idle <= 1'b0;"),
 ("M29", "UART tx stop bit is 0", "rtl/uart_tx.v", "sh <= {1'b1, data, 1'b0};", "sh <= {1'b0, data, 1'b0};"),
 ("M30", "UART tx start bit is 1", "rtl/uart_tx.v", "sh <= {1'b1, data, 1'b0}; busy <= 1'b1; n <= 4'd0; cnt <= 16'd0; txd <= 1'b0;", "sh <= {1'b1, data, 1'b1}; busy <= 1'b1; n <= 4'd0; cnt <= 16'd0; txd <= 1'b1;"),
 ("M31", "UART tx bit time is one clock short", "rtl/uart_tx.v", "end else if (cnt == CLKS_PER_BIT - 1) begin", "end else if (cnt == CLKS_PER_BIT - 2) begin"),
 ("M32", "UART rx shifts MSB first", "rtl/uart_rx.v", "sh <= {rx, sh[7:1]};", "sh <= {sh[6:0], rx};"),
 ("M33", "UART tx idles low after reset", "rtl/uart_tx.v", "busy <= 1'b0; txd <= 1'b1; n <= 4'd0; cnt <= 16'd0; sh <= 10'h3FF;", "busy <= 1'b0; txd <= 1'b0; n <= 4'd0; cnt <= 16'd0; sh <= 10'h3FF;"),
 ("M35", "UART rx idle filter too short (phantom high after reset re-arms it)", "rtl/uart_rx.v", "else if (cnt == 16'd3) wait_idle <= 1'b0;", "else if (cnt == 16'd0) wait_idle <= 1'b0;"),
 ("M34", "UART rx accepts any start-bit glitch (no mid-bit check)", "rtl/uart_rx.v", "if (!rx) begin bi <= 3'd0; st <= 2'd2; end else st <= 2'd0;", "begin bi <= 3'd0; st <= 2'd2; end"),
 ("M36", "clear key not edge-triggered (level clears)", "rtl/button_debounce.v", "press_pulse <= in_pressed & armed;", "press_pulse <= in_pressed;"),
 ("M37", "debounce never arms after warm-up (no clear possible)", "rtl/button_debounce.v", "else if (!pressed && !in_pressed) armed <= 1'b1;", "else if (1'b0) armed <= 1'b1;"),
 ("M38", "clear key bypasses debounce", "rtl/de2_115_top.v", ".fault_clear(clear_pulse)", ".fault_clear(~KEY[1])"),
 ("M39", "e-stop key routed through debounced clear path (slow stop)", "rtl/de2_115_top.v", ".estop_n(KEY[0] & ESTOP_EXT_N)", ".estop_n(KEY[0] & ESTOP_EXT_N & ~clear_db)"),
 ("M40", "reset not synchronised on release (raw KEY[3] into the wrapper)", "rtl/de2_115_top.v", "reset_sync u_rst (.clk(CLOCK_50), .arst_n(KEY[3]), .rst_n(rst_n));", "assign rst_n = KEY[3];"),
 ("M41", "reset_sync releases after one stage", "rtl/reset_sync.v", "else         sr <= {sr[STAGES-2:0], 1'b1};", "else         sr <= {STAGES{1'b1}};"),
 ("M42", "PWM ignores the kill input", "rtl/pwm_generator.v", "(cnt[11:4] < duty_active) & ~kill;", "(cnt[11:4] < duty_active);"),
 ("M43", "governor does not zero the command on trip", "rtl/safety_governor.v", "cmd_out       <= trip ? 8'd0 : ai_cmd;", "cmd_out       <= ai_cmd;"),
 ("M44", "invalid ADC no longer trips the governor", "rtl/safety_governor.v", "estop_active | adc_invalid | ~armed", "estop_active | ~armed"),
 ("M45", "AI class 2 can RAISE the command to HOLD_CAP", "rtl/safety_governor.v", "(lut_cmd < HOLD_CAP)   ? lut_cmd : HOLD_CAP;", "HOLD_CAP;"),
 ("M46", "force limit comparison disabled", "rtl/safety_governor.v", "if (force_code >= FORCE_MAX)      force_over_n = 1'b1;", "if (force_code > 12'hFFF)      force_over_n = 1'b1;"),
 ("M47", "governor reset leaves safe_state low", "rtl/safety_governor.v", "cmd_out <= 8'd0; safe_state <= 1'b1;", "cmd_out <= 8'd0; safe_state <= 1'b0;"),
 ("M48", "PWM loads the duty every clock (not only at the period boundary)", "rtl/pwm_generator.v", "if (cnt == 12'hFFF) duty_active <= duty;", "duty_active <= duty;"),
 ("M49", "PWM compare uses <= (a zero duty still gives a pulse)", "rtl/pwm_generator.v", "(cnt[11:4] < duty_active) & ~kill;", "(cnt[11:4] <= duty_active) & ~kill;"),
]
def run_one(m, jobs):
    mid, name, f, old, new = m; d = tempfile.mkdtemp(prefix=f"mut_{mid}_")
    try:
        for sub in ("rtl", "tb", "sim"): shutil.copytree(os.path.join(ROOT, sub), os.path.join(d, sub), ignore=shutil.ignore_patterns("build", "*.vvp", "__pycache__"))
        os.makedirs(os.path.join(d, "results"))
        p = os.path.join(d, f); t = open(p).read()
        if t.count(old) != 1: return mid, name, "INVALID", f"pattern found {t.count(old)} times"
        open(p, "w").write(t.replace(old, new))
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "run_regression.py"), "--root", d, "--jobs", str(jobs), "--builddir", os.path.join(d, "b"), "--log", os.path.join(d, "l.txt"), "--json", os.path.join(d, "j.json"), "--timeout", "300"], capture_output=True, text=True)
        summ = json.load(open(os.path.join(d, "j.json"))) if os.path.exists(os.path.join(d, "j.json")) else None
        if summ is None: return mid, name, "INVALID", r.stdout[-200:]
        bad = [t_ for t_ in summ["per_testbench"] if t_["status"] != "PASS"]
        if any("compile error" in " ".join(t_["problems"]) for t_ in bad): return mid, name, "INVALID", "compile error: " + bad[0]["problems"][0][:120]
        return mid, name, ("KILLED" if r.returncode != 0 else "SURVIVED"), ",".join(t_["name"] for t_ in bad)
    finally: shutil.rmtree(d, ignore_errors=True)
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--only"); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--json", default=os.path.join(ROOT, "results", "mutation_report.json"))
    a = ap.parse_args(); ms = [m for m in M if not a.only or m[0] in a.only.split(",")]
    with ThreadPoolExecutor(a.jobs) as ex: res = list(ex.map(lambda m: run_one(m, 1), ms))
    for mid, name, st, by in res: print(f"{mid} {st:9s} {name}   [{by}]")
    k = sum(r[2] == "KILLED" for r in res); s = sum(r[2] == "SURVIVED" for r in res); inv = sum(r[2] == "INVALID" for r in res)
    print(f"\nmutants {len(res)}: killed {k}, survived {s}, invalid {inv}; mutation score (killed / valid) = {100 * k / max(1, k + s):.1f}%")
    os.makedirs(os.path.dirname(a.json), exist_ok=True)
    with open(a.json, "w") as fh: json.dump(dict(mutants=[dict(id=r[0], name=r[1], status=r[2], detected_by=r[3]) for r in res], killed=k, survived=s, invalid=inv), fh, indent=1)
    return 0 if (s == 0 and inv == 0) else 1
if __name__ == "__main__": sys.exit(main())
