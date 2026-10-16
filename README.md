# ADHRC – Stage 1 (FPGA core, board-independent)

## Files
| File | Purpose |
|---|---|
| rtl/servo_pwm_generator.v | 50 Hz servo pulse, width in µs, glitch-free (latched per frame) |
| rtl/lut_engine.v | 64-entry force→pulse LUT, two banks, 1-clock lookup, atomic swap |
| rtl/safety_governor.v | Hard clamp, over-force (hysteresis), sensor range fault, ADC timeout, e-stop, grip enable |
| rtl/reflex_top.v | Wires it together; button synchronizers |
| tb/tb_reflex_top.v | Self-checking testbench (prints PASS/FAIL) |
| python/lut_gen.py | 3 parameters → validated 64-entry LUT hex file |
| rtl/adc_spi_interface.v | MCP3008 SPI master (mode 0, 17-clock single-ended frame) |
| tb/mcp3008_model.v | **Simulation-only** MCP3008 model with datasheet timing checks |
| tb/tb_adc_spi_interface.v | Self-checking ADC interface testbench |
| tb/tb_adc_bad_param.v | Negative test: must **fail** to compile (SCLK too fast) |
| run_sim.sh | Runs all tests; exits nonzero on any failure |
| rtl/reflex_top_spi.v | **Stage 2 top**: adc_spi_interface + unchanged reflex_top, continuous sampling of channel 0 |
| tb/tb_reflex_top_spi.v | Stage 2 integration testbench (real MCP3008 model, real ADC timeout) |
| tb/tb_governor_boundary.v | Safety-governor threshold boundaries: 899/900, 799/800, 1014/1015 |
| rtl/uart_rx.v | **Stage 3**: UART receiver, 8N1, configurable `CLK_HZ`/`BAUD` |
| rtl/lut_upload_ctrl.v | **Stage 3**: packet parser / upload sequencer driving `lut_engine`'s write and swap ports |
| rtl/reflex_top_uart.v | **Stage 3 top**: `uart_rx` + `lut_upload_ctrl` + unchanged `reflex_top_spi` (Stage 4 adds `uart_tx` + `upload_resp_tx`, additive ports only) |
| rtl/uart_tx.v | **Stage 4**: UART transmitter, 8N1, same `CLK_HZ`/`BAUD` parameters as `uart_rx` |
| rtl/upload_resp_tx.v | **Stage 4**: turns controller ACK/NAK events into 4-byte response frames, with a small FIFO |
| tb/tb_uart_rx.v, tb/tb_lut_upload_ctrl.v, tb/tb_reflex_top_uart.v | Stage 3 self-checking tests |
| tb/tb_uart_tx.v, tb/tb_upload_resp_tx.v, tb/tb_reflex_top_host.v, tb/uart_monitor.v, tb/tb_uart_tx_bad_param.v | Stage 4 tests (`uart_monitor.v` is a sim-only independent line decoder) |
| tb/tb_uart_bad_param.v | Negative test: must **fail** to compile (baud too fast for the clock) |

## Run the simulation (no board needed)
**EDA Playground (browser):** edaplayground.com → paste `tb_reflex_top.v` in the left
(testbench) pane, add the four `rtl/` files in the right pane (+ button), select
*Icarus Verilog 12*, tick *Open EPWave after run*, click Run.

**Laptop:** install Icarus Verilog + GTKWave, then
```
iverilog -o sim rtl/*.v tb/tb_reflex_top.v
vvp sim
gtkwave dump.vcd
```
Expected last line: `=== DONE: 0 error(s) ===`

Run everything at once (Icarus Verilog installed): `sh run_sim.sh`
It ends with `ALL TESTS PASSED` and exit code 0, or `SOME TESTS FAILED` and exit code 1.

**EDA Playground, one testbench at a time** (two testbenches in one run clash):
- Stage 1: testbench pane `tb_reflex_top.v`; design pane the four core `rtl/` files.
- ADC: testbench pane `tb_adc_spi_interface.v`; design pane `adc_spi_interface.v`
  and `mcp3008_model.v`. Never add `tb_adc_bad_param.v` to a normal run.

## What the waveforms should look like
- **servo_out:** one high pulse per frame. Width: 2000 µs at no force, getting
  shorter as adc_value rises, 1000 µs (open) in any fault.
- **adc_valid:** short pulse every 50 µs (fake ADC in the testbench).
- **dbg_cmd_toggle:** flips 2 clocks after every adc_valid. This is the pin you
  will probe on the oscilloscope for the FPGA latency measurement.
- **fault_led:** `0001` over-force, `0010` sensor range, `0100` ADC timeout,
  `1000` e-stop. Only over-force clears by itself; the rest need reset.

## Simulation shortcuts (testbench only)
1 MHz clock and a 2.5 ms frame instead of 20 ms, so the sim runs in seconds.
The real design uses the board clock (`CLK_HZ`) and 20 ms.

## Placeholders – NOT final values
`FORCE_MAX`, `FORCE_RESUME`, `ADC_FAULT_HI` and the default LUT curve are
placeholders. They get replaced with numbers from the Week-2 FSR calibration.

## Known limitation
With FSR-to-3.3 V and 10 kΩ-to-ground, a broken FSR wire reads 0, which looks
the same as "no force". The governor can't detect that case; mention it in the report.

## ADC interface (MCP3008) – timing assumptions
- SPI mode 0. MOSI changes on falling SCLK; MISO sampled on rising SCLK through a
  2-flop synchronizer. Frame: start, SGL=1, D2 D1 D0, null bit, B9..B0 (17 clocks).
- `SCLK_HZ` default 1 MHz, allowed 10 kHz–1.35 MHz (1.35 MHz is the datasheet limit
  at 2.7 V, so it is safe at 3.3 V). Real SCLK is rounded *down*, never above the setting.
- Needs `CLK_HZ >= 16 × SCLK_HZ`; invalid settings stop compilation.
- Theoretical (simulated, not measured) conversion period: `35·HALF + 1` clocks
  → about 17.5 µs at 100 MHz / 1 MHz (≈57 kS/s).
- `frame_err`: null bit read as 1 → no `data_valid`. With the MISO pull-up enabled,
  a disconnected MISO is detected this way; the safety governor's ADC timeout then
  trips because no valid samples arrive. MISO stuck **low** reads as 0 = "no force"
  and is **not** detectable.
- Source impedance: the FSR divider can be up to ~10 kΩ. If readings look low or noisy
  on hardware, try a lower `SCLK_HZ` (e.g. 500 kHz) and compare (Week 2 check).

## Stage 2 – SPI ADC integrated with the reflex core
`reflex_top_spi.v` wires `adc_spi_interface` (channel fixed to 0, `start = ~busy`) to the
unchanged `reflex_top` (`data` -> `adc_value`, `data_valid` -> `adc_valid`). Same clock, so no
clock-domain crossing. Only `data_valid` (frame with null bit = 0) feeds the governor's ADC
timeout; requests and `frame_err` frames never do, so a dead or disconnected ADC trips the
existing timeout fault (~57 samples per 1000 us window at 100 MHz / 1 MHz).
- `ADC_TIMEOUT_US` in `reflex_top_spi.v` is a copy of the governor default (1000): change both.
- The wrapper refuses to compile if fewer than 4 samples fit in the timeout window
  (e.g. SCLK_HZ = 10 kHz would trip a healthy sensor).
- Run only the integration test on EDA Playground: testbench pane `tb_reflex_top_spi.v`;
  design pane the four core `rtl/` files + `adc_spi_interface.v` + `reflex_top_spi.v` +
  `mcp3008_model.v` (about 29 ms simulated; slower than the others).
- Latency CS rise -> `dbg_cmd_toggle` is 2 clocks in simulation only; real hardware adds I/O delays.
- Not yet done: synthesis/timing, pin constraints (board model not confirmed), pull-up on MISO,
  hardware measurements.

## Regression suite (`run_sim.sh`)
`sh run_sim.sh` runs the default suite (about 1 minute) and prints a per-test summary
(reflex, boundary, adc, adc_27m, spi_top, bad_param); `sh run_sim.sh --extended` also runs
`spi_top_20ms`: the integration test at 100 MHz with the real 20 ms servo frame (about 3 min).
Exit status is nonzero if any test fails. Generated files (`sim_*`, `*.log`, `*.vcd`) are in `.gitignore`.

### Running the governor boundary test (`tb/tb_governor_boundary.v`)
It drives `reflex_top` directly (no SPI) and uses only the four Stage 1 RTL modules.
- Local: `iverilog -g2005 -o sim_boundary rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v tb/tb_governor_boundary.v && vvp -n sim_boundary`
  (or just `sh run_sim.sh`, which runs it as `boundary`).
- EDA Playground: testbench pane `tb_governor_boundary.v`; design pane the four core `rtl/` files
  (`reflex_top.v`, `lut_engine.v`, `safety_governor.v`, `servo_pwm_generator.v`).
- Expected: 16 `PASS` lines and a last line `=== DONE: 0 error(s) ===`.

### Extended integration test (100 MHz clock, real 20 ms servo frame)
The default `spi_top` test uses a 2.5 ms servo frame to stay fast. The extended run uses the real
20 ms frame and takes about 3 minutes.
- Local, via the script: `sh run_sim.sh --extended` (or `EXTENDED=1 sh run_sim.sh`). It runs the default
  suite plus `spi_top_20ms`.
- Local, one test only:
  `iverilog -g2005 -Ptb_reflex_top_spi.FRAME_US=20000 -Ptb_reflex_top_spi.WATCHDOG_NS=900000000 -o sim_spi_20ms rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v && vvp -n sim_spi_20ms`
- EDA Playground (no `-P` parameter overrides): testbench pane `tb_reflex_top_spi.v`; design pane the four
  core `rtl/` files + `adc_spi_interface.v` + `reflex_top_spi.v` + `mcp3008_model.v`. In the testbench pane,
  edit the two defaults before running: `parameter FRAME_US = 2500;` -> `20000` and
  `parameter WATCHDOG_NS = 300_000_000;` -> `900_000_000`. Do not copy the edited testbench back to the repo.
  The run is long (about 3 minutes on a laptop), so it may exceed EDA Playground's time limit. That
  procedure has not been tried on EDA Playground.

Integration test (`tb_reflex_top_spi.v`) also covers a reset in the middle of a conversion and
MISO stuck low. Stuck-low is a **known undetectable fault**: every frame looks valid and reads
0 (no force), so no fault is raised; the test documents that behaviour, it is not a protection.
A disconnected (open) MISO *is* detected, through the null bit and the ADC timeout.
All results are simulation only; nothing here is validated on hardware.

## Stage 3 – UART LUT upload (simulation only)
Lets a host replace the 64-entry force->pulse table over a serial line:
`uart_rx -> lut_upload_ctrl -> lut_engine` (existing `wr_en/wr_addr/wr_data/swap` ports) -> bank swap.
`reflex_top`, `reflex_top_spi`, `lut_engine`, `safety_governor` and `servo_pwm_generator` are **unchanged**;
`reflex_top_uart.v` is a new top that only connects to their existing ports. The safety governor still
clamps every command to 1000..2000 us, so an uploaded table can never exceed the hard limits.

### Assumptions (PLACEHOLDERS, set per board and host)
`CLK_HZ = 100 MHz`, `BAUD = 115200` (8N1, LSB first), `UPLOAD_TIMEOUT_US = 10000`. No board, pin or baud
rate has been chosen. `CLKS_PER_BIT = round(CLK_HZ/BAUD)` must be >= 8; `CLK_HZ` must be a whole number of MHz.
At 100 MHz / 115200 that is 868 clocks per bit.

### Upload protocol (host -> FPGA; replies are added in Stage 4 below)
Packet: `0xA5 | CMD | payload | CHK`, `CHK = CMD ^ every payload byte`. Fixed lengths, no length byte, no byte stuffing.

| CMD | Name | Payload | Effect |
|---|---|---|---|
| 0x01 | BEGIN | none | Starts an upload; forgets all received entries and any earlier failure. |
| 0x02 | WRITE | `ADDR` (0..63), `DATA_H`, `DATA_L` | Entry `ADDR` = `{DATA_H[3:0], DATA_L}` us, into the **inactive** bank. |
| 0x03 | COMMIT | none | One bank swap, only if all 64 **distinct** addresses were written and nothing failed. |
| 0x04 | ABORT | none | Cancels the upload. No swap. |

Typical session: `BEGIN`, 64 x `WRITE` (any order, duplicates allowed), `COMMIT`.
Example: BEGIN = `A5 01 01`; WRITE addr 5 = 1500 us (0x05DC) = `A5 02 05 05 DC 02^05^05^DC` = `A5 02 05 05 DC DE`.

**Validity rules.** `ADDR < 64`; `DATA_H[7:4] = 0`; `1000 <= value <= 2000` (mirrors the governor limits).
A WRITE outside an active, not-failed upload is refused. COMMIT counts distinct addresses (a 64-bit set), not
WRITE commands: 64 writes to one address, or 64 writes covering 63 addresses, do not commit. A partial table
is never swapped in because the inactive bank holds the OLD table, so missing entries would come back as stale values.
Any NAK while an upload is active marks it **failed**: WRITE and COMMIT are refused (ERR_FAILED) until a new BEGIN.
BEGIN and ABORT always work. COMMIT on success also closes the upload, so a later WRITE cannot touch the bank
that just became inactive without a new BEGIN. The live (active) bank is only ever changed by the swap.

**Error codes** (`upload_err`, last NAK, cleared by BEGIN/reset): 1 CHK, 2 CMD, 3 NOT_ACTIVE, 4 FAILED, 5 ADDR,
6 DATA (upper nibble), 7 RANGE, 8 INCOMPLETE, 9 TIMEOUT, 10 UART (framing error).

**Framing and recovery.**
- Waiting for a packet, every byte except `0xA5` is ignored (leading garbage is skipped). An idle gap between packets
  is fine and does not cancel an upload.
- `0xA5` is an ordinary data value inside a packet (e.g. `DATA_L = 0xA5`, or a checksum of 0xA5), so it cannot be used
  to resynchronise inside a packet. Instead: after an error where packet boundaries can no longer be trusted
  (bad checksum, unknown CMD, UART framing error) the controller enters QUIET: it ignores all bytes, with no ACK/NAK,
  until the line has been idle for `TIMEOUT_US`, then looks for `0xA5` again.
  **The host must therefore pause >= `UPLOAD_TIMEOUT_US` before its next packet after such an error; a packet sent
  sooner is swallowed.** With Stage 4 the host sees the NAK as a response frame; the packet is
  still swallowed, so wait the timeout before the next one (and restart from BEGIN if the upload failed).
- Gap > `TIMEOUT_US` inside a packet: packet dropped, NAK ERR_TIMEOUT, upload failed, parser back at SOF
  (no QUIET: the line is already idle). Recovery: send a fresh BEGIN.
- Errors on a complete, checksum-valid packet (bad address/data, wrong state, incomplete COMMIT) return straight to SOF.
- Reset clears the parser and the upload (active/failed/received set); the live table is kept. An interrupted upload needs a new BEGIN.

**Checksum limits.** XOR catches any single corrupted byte and odd bit flips per bit position, but not compensating
errors (two bytes flipping the same bit, swapped bytes). It is a noise check, not authentication; anyone who can
reach the serial pin can upload a table (still clamped to 1000..2000 us by the governor).

### Module interfaces
`uart_rx #(CLK_HZ, BAUD)`: `clk, rst, rx` -> `data[7:0], valid` (1-clock), `frame_err` (1-clock, stop bit low;
waits for the line to go high again so a break gives one error), `busy`. Mid-bit sampling, 2-flop synchronizer,
start-bit glitch rejection, back-to-back frames.
`lut_upload_ctrl #(CLK_HZ, TIMEOUT_US, PULSE_MIN, PULSE_MAX)`: in `rx_data, rx_valid, rx_frame_err`; out `lut_wr_en,
lut_wr_addr[5:0], lut_wr_data[11:0], lut_swap` (all registered, 1-clock pulses; never a write and a swap in the same clock),
`ack, nak, commit_done` (pulses), `err_code[3:0], upload_active, upload_failed, entries[6:0]` (distinct addresses).
`reflex_top_uart`: adds `uart_rxd` and the `upload_*` status outputs to the Stage 2 ports.
Keep `PULSE_MIN/PULSE_MAX` equal to the governor's `PULSE_MIN_US/PULSE_MAX_US`.

### Tests (all in `sh run_sim.sh`)
| Test | Covers |
|---|---|
| `uart_rx` (+ `uart_rx_27m`, `uart_rx_1m`) | frames 00 FF 55 AA A5 ..., back-to-back, +-3 % baud error, framing error, break, glitch, reset mid-frame; 100 MHz/115200, 27 MHz/115200, 100 MHz/1 Mbaud |
| `lut_ctrl` | `lut_upload_ctrl` + the real `lut_engine`, live table read back after every scenario: full upload, partial (63), duplicates, bad address/data/range (incl. 999/2001 and 1000/2000 boundaries), no BEGIN, ABORT, checksum/CMD errors and QUIET, garbage and 0xA5 payloads, timeout, idle gap, UART framing error, reset mid-upload/packet |
| `uart_top` | serial bytes -> unchanged reflex path with the MCP3008 model: servo output unchanged after partial, 64-but-uncommitted, aborted, timed-out and invalid uploads; changes only after a valid COMMIT; governor still opens on over-force; table survives reset |
| `uart_bad_param` | baud too fast for the clock must not compile |

Run one: `iverilog -g2005 -o sim_x rtl/lut_engine.v rtl/lut_upload_ctrl.v tb/tb_lut_upload_ctrl.v && vvp -n sim_x`.
EDA Playground (one testbench per run, not tried there): `tb_uart_rx.v` + `uart_rx.v`; `tb_lut_upload_ctrl.v` +
`lut_engine.v` + `lut_upload_ctrl.v`; `tb_reflex_top_uart.v` + the four core `rtl/` files + `adc_spi_interface.v` +
`reflex_top_spi.v` + `uart_rx.v` + `lut_upload_ctrl.v` + `reflex_top_uart.v` + `mcp3008_model.v` (about 27 ms simulated).
The Stage 3 integration test uses 2 Mbaud and a 200 us timeout only to keep simulation short; the extended 20 ms
run (`--extended`) still covers the Stage 2 path only.

### Limitations and next steps
- Simulation only: no synthesis, timing, FPGA or hardware validation; baud, clock and timeout are placeholders.
- (Stage 3 had no reply path; Stage 4 below adds it.)
- Monotonic-table and "never tighten the grip as force rises" rules exist only in `python/lut_gen.py`, not in hardware;
  hardware enforces only 1000..2000 us (plus the governor clamp).
- Pull-up/pin settings for `uart_rxd` are not defined (board not confirmed); an idle-low or floating line would
  likely appear as framing errors (not tested on hardware).
- By design the swap is a single-clock bank toggle and writes only touch the inactive bank, so a reset in the middle of an
  upload leaves the live table intact (tested for reset mid-upload and mid-packet; a power loss exactly at COMMIT is not
  analysed or tested). A partially written inactive bank is simply discarded.
- `python/lut_send.py` (host-side packet builder) is intentionally not included yet.

## Stage 4 – UART transmitter and host-visible responses (simulation only)
`uart_tx` (8N1, LSB first) and `upload_resp_tx` send a response frame to the host for every upload ACK or NAK.
`lut_upload_ctrl`, `uart_rx` and all Stage 1/2 RTL are **unchanged**. `reflex_top_uart` gained only additive items:
parameter `RESP_FIFO_DEPTH` (default 4) and outputs `uart_txd`, `tx_busy`, `resp_overflow`; its existing ports and
behaviour are untouched and the unmodified Stage 3 testbench still passes against it. `CLK_HZ`/`BAUD` are the same
PLACEHOLDERS as Stage 3 (100 MHz, 115200); no pin is assumed (`uart_txd` is a plain output port).

### Response frame (FPGA -> host): `0x5A | STATUS | INFO | CHK`, `CHK = STATUS ^ INFO`
| STATUS | Meaning | INFO |
|---|---|---|
| `0x06` | ACK: command accepted | distinct entries received so far (0..64) |
| `0x07` | COMMITTED: COMMIT accepted and the bank swap happened | 64 |
| `0x15` | NAK: command rejected | error code 1..10 (table in Stage 3: 1 CHK, 2 CMD, 3 NOT_ACTIVE, 4 FAILED, 5 ADDR, 6 DATA, 7 RANGE, 8 INCOMPLETE, 9 TIMEOUT, 10 UART) |

STATUS bit 7 (`0x80`) = one or more earlier responses were dropped right before this one (see overflow).
Examples: BEGIN accepted `5A 06 00 06`; 37th distinct entry written `5A 06 25 23`; COMMIT done `5A 07 40 47`;
incomplete COMMIT `5A 15 08 1D`; same ACK after a loss `5A 86 25 A3`.
`0x5A` appears **only** as the first byte: INFO <= 64, STATUS is `06/07/15` (+`0x80`) and `STATUS ^ INFO` is never
`0x5A` (checked exhaustively in `tb_upload_resp_tx`). Responses are in command order. No command echo: the host matches
by order, except codes 9 (TIMEOUT) and 10 (UART framing error), which are asynchronous and have no command of their own
(the timeout NAK arrives about `UPLOAD_TIMEOUT_US` after the last byte of an incomplete packet).
Bytes the controller ignores (garbage before `0xA5`, packets swallowed in the quiet period) get **no** response.

**Truthfulness.** A response is generated from the controller's own ack/nak event, in the same clock as its effect:
`COMMITTED` only when `lut_swap` fired (the integration test checks the swap pulse, the commit pulse, the bank LED and the
servo command), `ACK` for WRITE only when exactly one write reached `lut_engine`, and every `NAK` only when no write and
no swap occurred. `ACK` for ABORT/BEGIN means no write or swap.

**Host parser (the algorithm the tests use).** Hunt for `0x5A`. Read STATUS, INFO, CHK. If a `0x5A` appears where one of
those three bytes should be, drop the partial frame and treat that `0x5A` as a new start (this is how a frame cut off by a
reset is skipped). If CHK is wrong or STATUS/INFO is impossible (STATUS not in `06/07/15` after masking bit 7; INFO > 64
for ACK/COMMITTED, outside 1..10 for NAK), drop the frame and hunt again.

**Queueing, overflow, reset.** Events go into a FIFO (`RESP_FIFO_DEPTH`, default 4) and frames are sent in order with no
gap between them while any are waiting. A response is stored in exactly one place at a time: one of the `RESP_FIFO_DEPTH`
FIFO slots while it waits, or the separate current-frame register from the clock it is popped (it leaves the FIFO in that
same clock, so it is never counted twice) until its last (fourth) byte has been handed to `uart_tx`; that last byte then
finishes in the transmitter's own shift register and uses no response storage. A new response is accepted only if a FIFO
slot is free (the current-frame register is not part of that test), so storage capacity is `RESP_FIFO_DEPTH` waiting + 1
being sent = DEPTH+1: a burst faster than a frame can start (e.g. one event per clock into an idle, empty queue) is
accepted up to DEPTH+1 responses (5 for the default 4) and the rest are dropped. Under sustained traffic more are accepted
in total because frames keep leaving, and at one instant up to DEPTH+2 responses can still have bytes to send (the previous
frame's last byte is still on the wire). A 4-byte reply to a 3-byte command (BEGIN/COMMIT/ABORT) is slower than the commands, so a long burst of such
commands can fill the FIFO (WRITE, 6 bytes in, cannot). A response arriving while the FIFO is full is **dropped** (never
reordered); the next response that is queued carries the lost flag (one flag per gap, however many were dropped) and the
sticky `resp_overflow` output stays set until reset. Reset empties the FIFO, forgets a pending lost flag and drives `uart_txd`
high at once; a frame in flight is cut off (a truncated frame on the wire, then idle). Nothing is replayed after reset.

### Module interfaces
`uart_tx #(CLK_HZ, BAUD)`: `clk, rst, tx_data[7:0], tx_valid` -> `tx_ready, tx, busy`. A byte is accepted on a clock with
`tx_valid && tx_ready`; `tx_ready` is also high on the last clock of the stop bit, so holding `tx_valid` with the next byte
gives a continuous stream (10 bit times per byte). Every bit is exactly `round(CLK_HZ/BAUD)` clocks (>= 8 or elaboration fails);
the real baud differs from `BAUD` only by that rounding (0.006 % at 100 MHz/115200, 0.16 % at 27 MHz/115200).
`upload_resp_tx #(DEPTH)`: events `ev_ack, ev_nak, ev_commit, ev_err[3:0], ev_entries[6:0]` (wired to the controller's
`ack, nak, commit_done, err_code, entries`), byte interface to `uart_tx`, outputs `overflow`, `busy`. `DEPTH >= 2`.

### Tests (all in `sh run_sim.sh`)
| Test | Covers |
|---|---|
| `uart_tx` (+ `_27m`, `_1m`) | exact bit/frame timing (0x00 low for 9 bit times, start bit 1 bit time, start edges 10 bit times apart back to back), 12 awkward bytes decoded by an independent monitor and by `uart_rx`, ready/busy handshake, reset mid-byte and mid-stream; 100 MHz/115200, 27 MHz/115200, 100 MHz/1 Mbaud |
| `resp_tx` | every frame type and error code with exact bytes, all ACK counts 0..64, exhaustive `0x5A` uniqueness, back-to-back ordering and contiguity, overflow (accepts DEPTH+1 from an empty queue: DEPTH waiting + 1 being sent), repeated overflow, partial drain, lost-flag attachment and clearing, reset mid-frame and around events, parser resync on truncated/garbled synthetic streams |
| `host_top` | host model against the real `reflex_top_uart` + MCP3008 model: BEGIN/WRITE/duplicate/COMMIT/ABORT, incomplete COMMIT, every rejection (bad checksum, unknown CMD, bad address/data/range, no BEGIN), asynchronous timeout NAK, quiet period, pipelined 64-write upload (66 responses in order), burst of 40 BEGIN (drops flagged), reset during a response, each response compared with write/swap pulses, bank LED and servo command |
| `uart_tx_bad_param` | baud too fast for the clock must not compile |

EDA Playground (one testbench per run, not tried there): `tb_uart_tx.v` + `uart_tx.v` + `uart_rx.v` + `uart_monitor.v`;
`tb_upload_resp_tx.v` + `uart_tx.v` + `upload_resp_tx.v` + `uart_monitor.v`; `tb_reflex_top_host.v` + the four core `rtl/` files
+ `adc_spi_interface.v` + `reflex_top_spi.v` + `uart_rx.v` + `uart_tx.v` + `upload_resp_tx.v` + `lut_upload_ctrl.v` +
`reflex_top_uart.v` + `mcp3008_model.v` + `uart_monitor.v` (about 12 ms simulated). The host test uses 2 Mbaud and a 200 us
timeout only to keep simulation short; the extended 20 ms run (`--extended`) still covers the Stage 2 path only.

### Limitations and next steps
- Simulation only: no synthesis, timing, FPGA or hardware validation; clock, baud, timeout and FIFO depth are placeholders.
- No command echo, and no reply for ignored bytes: a host that pipelines commands can only align replies by order. Prefer
  stop-and-wait around BEGIN/COMMIT, and treat a missing reply as "ignored or swallowed".
- A burst of short commands (BEGIN/COMMIT/ABORT) can outrun the reply line; dropped replies are flagged on the next reply,
  but if nothing follows, the host never learns of the drop except through `resp_overflow` or a missing reply.
- A reply cut off by a reset reaches the host as a truncated frame (handled by the parser rule above); nothing is retransmitted.
- XOR check limits as in Stage 3; the response checksum only protects the host from line noise.
- `uart_txd` pin, idle level and any level shifting are undefined until a board is chosen. A host-side script that builds
  commands and parses replies (`python/lut_send.py`) is intentionally still not included.
