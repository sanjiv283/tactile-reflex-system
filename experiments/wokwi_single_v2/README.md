# Wokwi run (v2, time-based watchdog) - STATUS: NOT RUN IN WOKWI; unvalidated until real serial output is compared
1. https://wokwi.com -> sign in -> New Project -> ESP32 (Arduino).
2. Replace sketch.ino with the full contents of sketch_single.ino; replace diagram.json with this folder's diagram.json.
3. Click Start. Wait for the line `# SUITE DONE` in the Serial Monitor.
4. If the build fails (e.g. on ledcAttach, which needs Arduino-ESP32 core 3.x), copy the exact error text and the core version.
5. Click the Serial Monitor, Ctrl+A, Ctrl+C, paste into experiments/results_v2/wokwi_serial.txt (save the file).
6. Compare:
   diff <(grep -E '^(PARAM|LOG|CHK|SUM)' experiments/results_v2/wokwi_serial.txt | tr -d '\r') <(grep -E '^(PARAM|LOG|CHK|SUM)' experiments/results_v2/model_log.txt)
   Empty output = the sketch ran the same model logic as the host build. It says nothing about the RTL.
Do not compare with experiments/results/model_log.txt (old model).
