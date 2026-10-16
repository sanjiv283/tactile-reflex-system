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
`sh run_sim.sh` runs the default suite (about 2 minutes) and prints a per-test summary
(one line per test; the Stage 5 tests are listed below); `sh run_sim.sh --extended` also runs
`spi_top_20ms` (the integration test at 100 MHz with the real 20 ms servo frame) and the slower repeats of the Stage 5
tests (about 5-6 minutes in total).
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
  upload leaves the live table intact (tested for reset mid-upload and mid-packet; reset exactly around COMMIT is characterised under Stage 5 below; a power loss is not analysed). A partially written inactive bank is simply discarded.
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

## Stage 5 – Robustness and safety verification (simulation only)
Stage 5 added tests only. **No RTL was changed**: every test passed against the existing RTL, so no defect was found
and nothing was fixed. What the tests do pin down are exact behaviours (listed below), several of which were previously
only implied. Each new test was also run against deliberately broken copies of the RTL (24 mutations: governor, LUT engine,
servo, controller, response FIFO, top level) and fails on each, in the check written for it. One mutation (dropping the
combinational e-stop term from `trip`) was first missed; that led to the added "e-stop in the `lut_valid` clock" check.

### New tests (all in `sh run_sim.sh`; "ext" = only with `--extended`)
| Test | Checks |
|---|---|
| `gov_prio`, `gov_prio_cfg` | `safety_governor` driven directly, cycle-exact: clamp edges (PULSE_MIN-1 .. PULSE_MAX+1); thresholds follow the parameters (run with defaults and with FORCE_MAX 500 / RESUME 400 / FAULT_HI 600 / pulse 1200..1800 / SAFE 1500 / timeout 50); 1-clock e-stop pulse latches; e-stop held through reset re-latches; e-stop in the same clock as a sample, and in the same clock as `lut_valid` (only the combinational term in `trip` stops the value), never lets that sample's LUT value out; e-stop + range + over-force at once = `1011`, timeout adds `1111`, a low sample clears only over-force; exact ADC-timeout boundary; grip disable is not a fault, does not hide faults, and re-enabling waits for the next sample; a sample in the reset clock leaves no trace; `cmd_toggle` once per `lut_valid`; and every clock of the run: output inside the limits, SAFE whenever a fault has held 3 clocks |
| `reflex_sweep` | `reflex_top` against a reference model: all 1024 ADC codes rising, all codes falling from a trip (whole 800..949 hold band), 2500 pseudo-random samples concentrated at the thresholds, and 400 samples on consecutive clocks (each command appears exactly 2 clocks later, in order) |
| `servo_pwm` (+ ext `_50m`, `_27m`, `_100m`) | `servo_pwm_generator` directly, in clock counts: exact widths and exact frame period (real 20 ms frame at 1 MHz; 2.5 ms frame at 27/50/100 MHz), pulse latched once per frame (mid-pulse and mid-gap changes), width 0 = silent frame, reset mid-pulse |
| `lut_engine` | `lut_engine` directly: all 1024 codes against both banks, lookup timing and hold, writes never disturb the live bank (read in the same clock), swap atomic under a lookup every clock (old up to and including the swap clock, new from the next), two swaps = back, reset keeps tables and active bank |
| `ctrl_timing`, `ctrl_timing_2m` (+ ext `_50m`) | exact timeout and quiet-period boundaries of `lut_upload_ctrl` (see below), also that only CLK_HZ x TIMEOUT_US matters (TLIM 100, 50, 50) |
| `commit_race` | reset asserted at each clock from 3 before to 8 after the COMMIT byte (controller + real `lut_engine` + `upload_resp_tx`) |
| `resp_robust`, `_d3`, `_d8` (+ ext `_d2`, `_d5`) | `upload_resp_tx` at FIFO depths 2, 3, 4, 5, 8 (power-of-two and not): capacity DEPTH+1, order, lost flag, pointer wrap over many fills; reset at 102 different phases of a response frame |
| `safety_up` | full Stage 4 top: e-stop, over-force and ADC-timeout faults each held while a complete table is uploaded and committed; failed uploads (63 entries, invalid entry, ABORT, timeout) |
| `fault_latency` | fault applied at many offsets inside a servo frame (e-stop, over-force, grip disable), widths of the following pulses measured in clocks |
| `adc_50m`, `adc_16m`, `uart_rx_50m`, `uart_rx_min`, `uart_tx_50m`, `uart_tx_min` | supported configurations never simulated before: 50 MHz; the ADC at exactly CLK = 16 x SCLK (HALF = 8); both UARTs at the minimum 8 clocks per bit |
| `resp_bad_param`, `ctrl_bad_param`, `lint_rtl` | DEPTH = 1 and PULSE_MIN > PULSE_MAX must not elaborate; every RTL file compiles with `iverilog -Wall` and no warning |
| `gov_bad_*` (14) | `safety_governor` compile-only negative tests, one parameter changed per case, each rejected through its own named guard: `clk_low`/`clk_frac` (500 kHz, 1.5 MHz), `timeout` (0), `lim_order` (MIN > MAX; SAFE is then also out of range, so two guards fire), `lim_width` (MAX 4096), `pmin_neg` (MIN -1), `safe_low`/`safe_high` (500, 2001), `fmax_high`/`fmax_zero` (1024, 0), `fresume` (901 > 900), `fres_neg` (-1), `fhi_high`/`fhi_zero` (1024, 0) |
| `servo_bad_*` (3), `top_bad_frame` | `servo_pwm_generator`: `clk_low`/`clk_frac` (500 kHz, 1.5 MHz) and `frame` (FRAME_US = 2000); `top_bad_frame` reaches the same FRAME_US guard through `reflex_top` |
| `gov_ok_*` (3), `servo_ok_min`, `top_ok_frame` | compile-only acceptance with `-Wall` and no output: governor at the low and high ends of every range (incl. SAFE = MIN = MAX, RESUME = MAX, RESUME = 0, FAULT_HI = 1023) and with FAULT_HI < FORCE_MAX; servo at 1 MHz / FRAME_US = 2001; `top_ok_frame` is the valid twin of `top_bad_frame` (FRAME_US = 2001) |
| (runner) | a negative test passes only if iverilog fails and its output consists solely of "Unknown module type" errors for the expected guard name(s): a syntax error, missing file, extra missing module or wrong guard fails it |

### Behaviour now pinned down by tests (characterised, not changed)
- **Servo output after reset.** `servo_pwm_generator` clears its latched width in reset, so the first pulse after a reset
  starts one full frame later (20 ms with the real frame) and the first frame is empty. Output is low during reset.
- **Fault to servo pulse.** The command goes SAFE within a few clocks, but the PWM latches it once per frame. Measured
  (`fault_latency`; the exact window sizes are INFO-printed, the test asserts only that a fault reaches the next pulse unless it falls in a small window before the frame boundary, that the second pulse after it is always SAFE and that widths are never corrupt): the pulse already running keeps its old width; the next pulse is SAFE unless the fault came in the last
  5 clocks before the frame boundary (e-stop, grip disable) or the last 47 clocks (over-force, which arrives through an ADC
  sample; the test samples every 50 clocks); the pulse after that is always SAFE. So the old command can still be on the
  wire for the rest of the running pulse (up to 2 ms) and up to one frame, and in the worst case two frames, before a SAFE pulse starts.
- **Governor.** The e-stop input acts combinationally in `trip`; a 1-clock pulse latches. The ADC timeout does not fire if
  the next valid sample comes within `limit + 1` clocks of the previous one; `limit + 2` times out. Output never leaves
  1000..2000 us and is SAFE once a fault has held 3 clocks.
- **LUT engine.** `swap` flips the bank in one clock: the lookup in the swap clock still sees the old table, the next sees
  the new one. A write issued in the same clock as a swap lands in the bank being swapped in. `swap` and writes are not
  gated by reset (a swap pulse during reset still toggles the bank); reset keeps the tables and the active bank.
- **Controller timing.** Inside a packet the longest allowed distance between two byte-valid clocks is `TLIM + 1`
  (`TLIM = TIMEOUT_US x CLK_MHz`); `TLIM + 2` times out. In the quiet period (after CHK / CMD / UART errors) a byte at distance
  `TLIM + 1` from the previous byte is swallowed, at `TLIM + 2` it starts a packet; every byte received during quiet restarts the
  count. The Stage 3 text "a gap of TIMEOUT_US" means these exact values.
- **Reset around COMMIT** (`commit_race`). The live table is always entirely the old or entirely the new one. With `d` = clocks
  from the COMMIT's CHK byte valid clock to the start of a 2-clock reset (simulated, per-`d` results below):
  `d <= 0` cancels the COMMIT (no swap, upload gone); `d = 1` lets the swap happen (swap is not gated by reset) but the COMMITTED
  event is swallowed, so the table changed and the host gets no reply; from `d = 2` the event is queued in the response FIFO.
  **Queued is not delivered:** the frame is 4 bytes (about 350 us at 115200 baud) and a reset at any point until its last stop bit
  has been sent flushes the FIFO and cuts the frame off, although the swap has already happened. So the ambiguity window is not
  only the `d = 1` case: it lasts from the COMMIT until the COMMITTED frame is completely transmitted. Whenever the host sees
  no complete, valid COMMITTED frame around a reset, the outcome is unknown (old or new table); re-uploading the same table is safe.
  What `commit_race` **asserts**: live table all-old or all-new; swap pulse <=> new table live; no COMMITTED event without a swap;
  controller idle after a reset at or before the CHK byte; a COMMIT after the reset without BEGIN never swaps; the sweep covers
  both "committed with response" and "cancelled". What it only **prints (INFO)**: the per-`d` swap / response-queued / table
  split, and the counts of "swapped but response swallowed". The `d = 1` and `d = 2` outcomes above are therefore observations,
  not assertions, and "response queued" in that test means the event was pushed, not that a frame reached the host. The
  complete-frame side (a reset during any phase of a response frame truncates it and nothing is replayed) is asserted in `resp_robust`.

### Python LUT generator and generated-file loading (Stage 6B.2)
`sh run_sim.sh` (and `--extended`, which includes it) now also runs the Python side; set `PYTHON=...` to pick the interpreter
(default `python3`, else `python`; none found = a failing row, not a skip). All generated files live in one `mktemp -d`
directory that is removed at the end (and on interrupt); Python runs with `-B`, so no `__pycache__` appears.

| Test | What it checks |
|---|---|
| `lut_gen_selftest` | `python3 python/lut_gen.py --test` must exit 0 **and** print its success line |
| `lutload_default`, `lutload_clamped`, `lutload_mid` | the real `lut_gen.py` command line writes a hex file; `rtl/lut_engine.v` loads it through `INIT_FILE` (`$readmemh`, into both banks); `tb_lut_gen_load` looks up every one of the 64 entries (ADC codes 16i, 16i+7 and 16i+15 each) in bank 0 and, after one swap, in bank 1, plus the ADC 0 / ADC 1023 end entries, and compares with the values `lut_gen.make_lut()` produces as a decimal file (different code path and representation). Fixtures: default (2000..1000 us), both limits clamped (1800..1000 us), and a shallow slope (1500..1311 us, 64 distinct values, so an ordering or offset error cannot hide) |
| `lutload_short`, `lutload_missing` | **characterisation, not a requirement**: a file with only 10 words, or a file that does not exist, is NOT rejected by the RTL; the entries it does not provide read as unknown (`x`) in both banks (checked with `===`, not by the simulator's warning text) |
| `initsafe_range`, `initsafe_short`, `initsafe_missing` | Stage 6B.3, whole `reflex_top` with `LUT_INIT_FILE`: out-of-range words are clamped (asserted); unprovided entries -> `x` reaches governor output and `servo_out`, and e-stop / over-force / reset replace it with SAFE (SIM CHARACTERISATION, four-state only); an entry present in the file works again after reset |
| `lutgen_rej_range`, `lutgen_rej_slope` | the generator refuses an out-of-range table and a grip-tightening table: nonzero exit, `validate()`'s message, no file written |

Limits: the RTL has no check that an init file is complete or in range, so an incomplete file leaves `x` entries (the
governor's clamp is then the only protection; this is not tested with `x` inputs). Only the generator's own `validate()` guards
tables. The built-in default table (2000 - 16*i, so entry 63 is 992) differs from `lut_gen.py`'s default in that one entry
(1000, clamped); the governor clamps 992 to 1000, so the servo output is the same. The built-in default itself is still checked
by `lut_engine`. `LUT_INIT_FILE` reaches the tops by plain parameter wiring. The generated-file loading test above drives
`lut_engine` directly; the Stage 6B.3 test below loads out-of-range, short and missing files through `reflex_top` only (not through
`reflex_top_spi` or `reflex_top_uart`, and not the generated full tables). Found by this stage: `lut_gen.py` crashed for any explicit `--max`
(including the example in its own docstring) because argparse floats reached the `:03x` formatting; `make_lut` now rounds
`p_max`, and the self-test checks integer entries for float arguments.

### LUT initialisation safety (Stage 6B.3) - audit result: no RTL change
**What the RTL does.** `lut_engine` fills both banks once, in an `initial` block: `$readmemh(INIT_FILE)` into each bank, or the
built-in 2000 - 16*i table when `INIT_FILE` is empty. Reset does not touch the memory or `active_bank` (only `lut_valid` and
`lut_pulse_us` are cleared); only an upload + COMMIT changes the contents afterwards. Initialisation-file validity is therefore a
separate matter from the runtime upload/commit path, which has its own checksum, 64-distinct-address and range checks.

**What a bad table can and cannot do.**
- *Out-of-range words (000, fff, 999, 2001, ...)*: the governor clamps every LUT word to PULSE_MIN..PULSE_MAX (1000..2000) before
  it becomes the command, and the servo generator only ever sees the clamped value. This is plain synthesisable logic, so it holds
  independently of the simulator. Tested through the whole top with a file containing such words (`initsafe_range`): the
  governor output equals the clamped value for entries 0..56 and stays within 1000..2000 us at those 57 sample points (one per
  entry, taken 250 clocks after the code changes), and the servo pulse is exactly 1000 and 2000 us for the two extreme words. This is a
  sampled check, not an every-clock monitor; the cycle-by-cycle clamp checks are in `gov_prio` and `safety_up`.
- *Words the file does not provide (short file, missing file)*: **four-state simulation only** - the entries stay `x`, `x` passes
  through the clamp's `?:` (condition unknown), becomes the governor output, and `servo_out` itself goes `x` once the generator
  latches it at a frame boundary. Nothing in the RTL notices or rejects this. Faults and reset are not affected: e-stop, an
  over-force/range/timeout fault or a reset each replace the command with SAFE (1000 us) even while an unknown entry is being
  sampled, and an over-force sample that lands on an unprovided entry never latches the `x` (`initsafe_short`, `initsafe_missing`;
  these checks are labelled SIM CHARACTERISATION in the testbench).
- *Real hardware has no `x`.* What an unprovided memory word holds in an FPGA (0, or whatever the tool fills) is tool-dependent and
  **not verified here**; if it is 0 the clamp turns it into 1000 us, which is inside the limits but is not a meaningful table value.
  Whether a missing file is an error or only a warning in a synthesis flow is likewise unverified (no Quartus run).

**Why no initialisation-valid flag was added.** A reliable one would have to prove that all 64 words were read and are in range.
`$readmemh` gives no success indication in Verilog-2005; testing for `x` needs `===`, which synthesis cannot implement (it would
silently become `==` and never fire), so such a flag would protect only the simulation and could be mistaken for a hardware
guarantee. A synthesisable alternative (a 64-bit "written" mask, as the upload controller already keeps for uploads) would need a
new write path for the initial contents or a broader redesign, and the clamp already bounds the output. Not implemented; decide
separately if a hardware-visible "table verified" state is wanted (options: generate the init file only with `lut_gen.py` and check
its checksum on the host; or have the host upload and COMMIT the table after every power-up, which gets the existing checks).

**Guarantees, stated plainly.** (1) Output pulse is always within 1000..2000 us or SAFE, for any 12-bit table word (simulated,
and plain logic). (2) The built-in table is used when no file is given (`lut_engine`, `reflex`). (3) A bad file is not detected;
generate files only with `python/lut_gen.py` (it validates) and treat a build/simulation warning from `$readmemh` as an error.
Not guaranteed: that an incomplete table gives a meaningful servo command, or what hardware holds in unprovided words.

### Open questions and limits
- **Parameter guards (Stage 6B.1).** `servo_pwm_generator` and `safety_governor` reject invalid `CLK_HZ`, `FRAME_US` and governor
  limit/threshold settings at elaboration (the tests are listed in the table above). Reasoning in the RTL comments: `CLK_HZ`
  must be a whole number of MHz (integer microsecond tick); the pulse limits must fit the 12-bit command and `SAFE_PULSE_US`
  must lie inside them (it bypasses the clamp); `FORCE_MAX` and `ADC_FAULT_HI` must be 1..1023 (10-bit ADC); `FORCE_RESUME`
  must not exceed `FORCE_MAX` (the set term wins, so a higher resume level would be ignored). Accepted on purpose:
  `FORCE_RESUME == FORCE_MAX` (no hysteresis), `FORCE_RESUME == 0` (over-force never clears until reset) and
  `ADC_FAULT_HI <= FORCE_MAX` (the range fault latches first). The tops pass only `CLK_HZ` and `FRAME_US` through, so those are
  the only guards a top-level user can hit; the governor thresholds are reachable only by instantiating `safety_governor`
  directly. `lut_engine` has no numeric parameters, so no guard. Every guard name has a negative test; not every sub-condition
  does (for example `CLK_HZ = 0` and `FRAME_US` below 2000 other than 2000 itself are covered only by the same condition).
- **Servo frame vs governor pulse maximum (not checkable locally).** The `FRAME_US > 2000` guard is an integration assumption
  based on the current `safety_governor` default `PULSE_MAX_US = 2000`, not a limit derived from the servo's 12-bit pulse input
  (up to 4095). A standalone combination with a governor `PULSE_MAX_US` above 2000 needs a correspondingly longer `FRAME_US`;
  the local guards do not validate relationships between parameters of different modules. The tops do not expose
  `PULSE_MAX_US`, so this cannot occur through them today.
- `uart_tx.tx` has no power-up value (a possible glitch before the first reset clock on hardware); revisit at board bring-up.
- Whether the one-empty-frame delay after reset is acceptable for the real actuator is a hardware question.
- `tb_reflex_top_spi` (SPI integration) is hard-wired to 100 MHz; 50 MHz is covered at unit level only (ADC, UARTs, servo).
- No coverage tool, formal check or second simulator: only Icarus Verilog 12 and `-Wall`. No synthesis, timing analysis or
  hardware validation of any kind.
