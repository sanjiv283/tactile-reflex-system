# Wokwi model (separate software model - not the FPGA RTL)

**Status: authored but NOT run in Wokwi.** The build container could not reach wokwi.com (proxy 403), so `diagram.json` was never loaded
and `sketch.ino` was never compiled with the ESP32 core. The shared logic (`reflex_model.h`, `scenarios.h`) is compiled and exercised on the host
by `experiments/model_host.c`. No Wokwi link exists yet.

## Run it (manual, ~5 minutes)
1. https://wokwi.com -> New Project -> ESP32 (Arduino). Needs the ESP32 Arduino core 3.x (`ledcAttach`); with core 2.x replace it with `ledcSetup`+`ledcAttachPin`.
2. Replace `sketch.ino` and `diagram.json`; add `reflex_model.h`, `scenarios.h`, `force_lut_table.h` from this folder as new files.
3. Start the simulation. The Serial Monitor prints `LOG/CHK/SUM` lines for all scenarios, then enters manual mode (pot = force, E-STOP and CLEAR buttons).
4. Copy the serial output to `experiments/results/wokwi_serial.txt` and verify it against the host log:
   `diff <(grep -E '^(LOG|CHK|SUM|PARAM)' experiments/results/wokwi_serial.txt | tr -d '\r') experiments/results/model_log.txt`
   An empty diff shows the sketch executes the same model logic as the host build. It says nothing about the RTL.
5. Click Share in Wokwi to get the project link and record it in the paper's reproducibility section.

Manual-mode drive: the white LED brightness is the 8-bit command (the DRV8871 input PWM stand-in); it is forced off in safe state.
