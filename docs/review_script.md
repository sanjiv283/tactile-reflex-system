---
title: "Review script: Latency-Optimal Tactile Reflex System"
---

**Format:** four presenters, 25 slides, about 20 minutes plus questions. Replace "Presenter 1 to 4" with your names.
**Deck:** `docs/tactile_reflex_system.pptx`. All results quoted below come from RTL simulation at 50 MHz and from the SIMULATED dataset. Say so out loud when you quote them.

| Presenter | Slides | Topic | Time |
|---|---|---|---|
| 1 | 1 to 6 | Problem, gaps, novelty, architecture, how it works | 5:00 |
| 2 | 7 to 11 | Circuit, hardware, Safety Governor, modules | 4:30 |
| 3 | 12 to 17 | Verification, waveforms, latency, predictive pre-limit | 5:30 |
| 4 | 18 to 25 | AI/ML, SDGs, uses, findings, conclusion | 5:00 |

# Presenter 1: problem, novelty and architecture (slides 1 to 6)

**Slide 1: Title (0:20)**
"Good morning. Our project is a Latency-Optimal Tactile Reflex System: an AI-assisted, deterministic FPGA controller for robotic gripper actuation. The target board is the Terasic DE2-115. I will introduce the problem and the idea, then Presenter 2 covers the circuit, Presenter 3 the verification and latency, and Presenter 4 the AI model and impact."

**Slide 2: AI advises, FPGA protects (1:00)**
"A gripper must react to excessive force immediately, and it should also understand what it is touching. Those are two different jobs, so we split them. The AI path classifies contact and predicts excessive force, but it runs on a laptop, so it can be late, wrong or absent. The FPGA path takes the ADC reading through a fixed-function table, a Safety Governor and PWM, with no CPU and no software loop in between. The rule that ties them together: if a hard limit is violated, the Governor overrides the AI, and the AI can only ever lower the command, never raise it."

**Slide 3: Research gaps (1:00)**
"We framed four needs. Keep machine learning out of the safety-critical path. Report sensing, inference and actuation latency separately instead of as one blended number. Make the AI-override behaviour reproducibly verifiable. And provide a low-cost open platform. The right column shows how this work responds to each. Note that this is our positioning; the supporting literature review is part of our write-up."

**Slide 4: Novel contributions (1:00)**
"We claim six design-level contributions. Advisory-only AI, checked with an always-wrong AI. A slope-predictive pre-limit in plain hardware. A self-checking AI link with automatic fall-back to FPGA-only. An instant PWM kill with a latched, fail-safe emergency stop. Separate latency reporting. And a low-cost open design. This is a technical description, not a prior-art or patentability conclusion."

**Slide 5: System architecture (0:45)**
"This is the architecture. The top row is the FPGA reflex path: sensor and ADC, fixed lookup table, Safety Governor, PWM, driver, actuator. The bottom row is the laptop: features, decision tree. The dashed red arrow is the only place the AI touches the control path, and it enters the Governor, not the driver."

**Slide 6: How it works (1:00)**
"Walking through it: the SPI ADC frame takes 104 clock cycles. Conditioning, lookup, governing and PWM each add one cycle. In parallel the FPGA sends the force to the laptop about every millisecond, the tree returns a class, and the FPGA checks the packet's checksum and heartbeat before using it. Example: force passes the limit while the AI says normal grip. The Governor trips and PWM is low four clocks, 80 nanoseconds, after the ADC sample. I will hand over to Presenter 2."

# Presenter 2: circuit, hardware and Governor (slides 7 to 11)

**Slide 7: Circuit diagram (1:00)**
"This is the wiring schematic. The FSR sits in a voltage divider with a 10 kilo-ohm resistor into the Pmod AD1 ADC, which is wired to the DE2-115 GPIO header over SPI. The FPGA outputs PWM to a DRV8871 driver, which drives the motor from a fused 12 volt supply. The emergency stop is a normally-closed contact, so an open contact or a cut wire reads as stop. The laptop connects over the board's RS-232 port. All grounds are common. The GPIO pin numbers are mapped from the board manual."

**Slide 8: Hardware, control and sensing (0:50)**
"The DE2-115 has a Cyclone IV E FPGA, a 50 megahertz clock, an RS-232 port and a 3.3 volt GPIO header. It has no ARM processor, which is why the AI runs on the laptop. The Pmod AD1 gives a 12-bit SPI ADC up to one megasample per second. The FSR 402 is a force-sensing resistor read through a divider."

**Slide 9: Hardware, actuation and safety (0:50)**
"The DRV8871 is a single H-bridge with PWM input and current limiting. The motor is a 12 volt geared DC motor whose stall current must stay under the 2 amp fuse. The emergency stop is a normally-closed mushroom button, and the supply has a bulk capacitor and fuse. The photo frames are placeholders for product photos."

**Slide 10: Safety Governor rules (1:00)**
"The Governor has six rules: maximum force with release hysteresis, sensor fault, emergency stop, invalid ADC value, a safe output state that forces PWM low on the very next clock, and the AI override. The first five are hard limits that nothing can bypass."

**Slide 11: Verilog modules (1:00)**
"These are the modules with the number of directed checks each passes: the ADC interface, input conditioning, the lookup table, the Governor, PWM, the fault handler, the AI interface, the UART link, the top level and the board wrapper. Every module has a testbench, a reset state and a synthesizable description. We also ran a generic yosys synthesis check with no latches or driver conflicts. Quartus synthesis and board bring-up are the next step. Over to Presenter 3."

# Presenter 3: verification, latency and prediction (slides 12 to 17)

**Slide 12: Verification results (1:00)**
"All 175 directed checks pass across 12 testbenches. Beyond those we replayed 1,800 vectors from the test set through the RTL twice: once with the model's real output, once with an AI that always claims normal grip. Both runs had zero safety violations. Cases covered include no, light and normal contact, high and excessive force, AI class changes and AI failure, emergency stop, sensor failure, reset, LUT boundaries, PWM, and the predictive pre-limit against its reference model."

**Slide 13: Simulation console (0:30)**
"This is the actual console output of the run-all script. Every testbench reports PASS with zero failures."

**Slide 14: AI overridden by the Governor (1:00)**
"This waveform is the key safety demonstration. The AI class stays at 2, normal grip, the whole time. Force steps above the maximum, safe state rises, and PWM falls low. The AI input was valid and was overridden. This is from RTL simulation at 50 megahertz."

**Slide 15: Emergency stop response (0:40)**
"The emergency stop input is synchronised, then latched. PWM is low five clock cycles, 100 nanoseconds, after the input edge, and the latch only releases through an operator clear."

**Slide 16: FPGA path latency (1:10)**
"Four numbers. ADC sample to PWM low is four cycles, 80 nanoseconds, with zero jitter. Emergency stop to PWM low is five cycles, 100 nanoseconds, zero jitter. The ADC frame takes 2.08 microseconds. A change at the ADC input reaches PWM low in 2.10 to 3.84 microseconds, a jitter of 1.74 microseconds, and all of that jitter comes from where the change lands in the ADC frame. These are RTL simulation cycle counts with an ideal ADC model. They exclude the analogue front end, driver and motor, and they are never added to the AI inference time."

**Slide 17: Predictive pre-limit (1:10)**
"This is our added hardware feature. The Governor measures how fast force rises over a 3 millisecond window and trips early if force plus two windows of rise would reach the limit. On the simulated test episodes it trips about 5.7 milliseconds before the hard limit on all 25 crossing episodes. The cost is that it also trips early on 6.5 percent of episodes that never reach the limit, 10 of 155. The RTL matches our Python reference model on all 4,720 vectors, and in a full-path test on a fast ramp it tripped at an ADC value of 2168 against 2568 for the hard limit alone. Parameters were chosen on training episodes only. Presenter 4 continues."

# Presenter 4: AI/ML, impact and conclusion (slides 18 to 25)

**Slide 18: Lightweight AI/ML model (0:45)**
"We used a decision tree of depth four with 16 leaves, because it is small, fast and interpretable. Six features: force, previous force, rate of change, moving average, contact duration and last delta. Classes are no contact, light contact, normal grip and excessive force. The data is simulated, labelled as such, and was split by episode: 420 for training and 180 for testing."

**Slide 19: AI/ML evaluation (1:00)**
"On the simulated test set accuracy is 91.9 percent, against 85.4 percent for a force-only baseline, so the dynamic features help. The confusion matrix shows where it errs: recall for excessive force is 72 percent, because some excessive-force samples are predicted as normal grip. That is exactly why the AI is not trusted for safety."

**Slide 20: AI inside the safety envelope (0:40)**
"Even when the AI is wrong, 88 out of 88 over-limit samples were forced to the safe state. The model's decision takes a median of about 11 microseconds on our development machine, between 6.6 and 11 across runs, and this will be re-measured on the final setup. T_FPGA and T_ML are reported separately and never summed."

**Slide 21: SDG alignment (0:40)**
"Primary alignment is SDG 9, innovation and infrastructure, and SDG 8, safer work with human-robot systems. Secondary links are health, food loss, education and inequality. We describe this as an enabling technology; we do not claim to achieve the goals."

**Slide 22: National and international uses (0:30)**
"Nationally: SME automation, rehabilitation, agriculture, logistics and education. Internationally: collaborative robotics, with ISO 10218 and ISO/TS 15066 as references only, low-resource assistive devices, hazardous handling and shared teaching benchmarks."

**Slide 23: Distinctive technical features (0:25)**
"The six features on this slide summarise the novelty: AI interpretation, fixed-function transfer, independent hardware governor, no software loop in the reflex path, bounded response and AI checked against hard limits."

**Slide 24: Key findings (0:35)**
"Four findings. Eighty-eight of 88 over-limit samples forced safe even against a hostile AI. A four-cycle logic path with zero jitter. The tree beats a force-only baseline, 91.9 to 85.4 percent, on simulated data. And since excessive-force recall is only 72 percent, the hardware limit has to stay authoritative."

**Slide 25: Conclusion (0:30)**
"In conclusion: a deterministic FPGA path enforces the hard limits, the AI adds contact classification and can only lower the command, and 175 checks plus 3,600 replayed vectors confirm the override behaviour in simulation. Next steps are board bring-up, real FSR data and re-measuring latency and inference time on hardware. Thank you. We are happy to take questions."

# Questions to rehearse

Answer these in your own words. Keep the facts below.

1. **Is the hardware built and tested?** State your real status. The results in the deck are RTL simulation and simulated data. Board bring-up, real sensor data and physical latency measurement are the next phase. Do not describe simulation numbers as measured on hardware.
2. **Why is the data simulated?** No recorded FSR data exists yet. The generator is in `ml/gen_sim_data.py`, labels come from the scenario that generated each episode, and the same pipeline accepts real recordings through `host/ai_host.py --log`.
3. **Class 3 recall is only 72 percent. Is that a problem?** It is the reason for the architecture. The AI never makes the final decision: 88 of 88 over-limit samples were forced safe even with an AI that always said normal grip.
4. **Why not put the AI in the control loop?** Latency and failure modes. Inference takes microseconds on a laptop plus a serial link, and it can be late, wrong or absent. The FPGA path is four clock cycles with zero jitter.
5. **What exactly is deterministic?** The FPGA logic path: ADC sample to PWM low is four cycles with zero jitter, and e-stop to PWM low is five cycles. The input-to-PWM time varies by 1.74 microseconds only because of where a change lands in the ADC frame.
6. **Why does the predictor trip early on non-crossing episodes?** Fast ramps look like they will cross the limit. Parameters were chosen on training episodes with a cap of 10 percent early trips, and the held-out test shows 6.5 percent. It can only make the system more conservative.
7. **What if the UART link fails?** Checksum, class/inverse check and a 10 millisecond heartbeat timeout mark the AI invalid, and the system falls back to FPGA-only control. Tested in `tb_de2_115_top` and `tb_uart_link`.
8. **What if the sensor wire breaks?** An open FSR reads as no contact, which cannot be detected from the ADC alone, so the emergency stop uses a normally-closed contact where a cut wire reads as stop. A silent ADC trips the watchdog, and frame errors or a railed reading trip the sensor fault.
9. **How do you know the tests can fail?** We deliberately broke the Governor (ignoring e-stop, off-by-one force limit, AI raising the command) and the tests caught each one. That exposed one missing test, which we added.
10. **Is this novel or patentable?** We describe design-level contributions and make no legal claim. A prior-art search is still to be done, especially for the rate-of-rise predictive limit.
11. **What is FORCE_MAX in newtons?** It is an ADC code of 2560 out of 4095. Converting to newtons needs a sensor calibration table, which is still to be collected.
12. **Do the SDG claims hold?** They are potential contributions of an enabling technology, not demonstrated outcomes.

# Delivery tips

- Rehearse hand-offs: each presenter's last sentence names the next presenter.
- Always say "simulated" when quoting results, and "RTL simulation" when quoting latency.
- If asked something you do not know, say what would settle it (a measurement, a datasheet or a literature check) and that you will follow up.
