# Script and narration transcript

Total length 7:05.67. Captions are shown on screen exactly as written here; the speech column is what the synthetic voice is given (acronyms spelled out for pronunciation).

## Scene 1 · INTRODUCTION  (0:00.00 – 0:19.27)

**0:00.80**  Tactile Reflex System.

**0:02.86**  A deterministic, FPGA-based safety reflex for robotic gripping.

> speech: A deterministic, F P G A based safety reflex for robotic gripping.

**0:07.70**  When a gripper squeezes too hard, the decision to stop must not wait for software.

**0:13.11**  Everything in this video is simulation. No physical hardware was tested.

## Scene 2 · THE PROBLEM  (0:19.27 – 0:58.83)

**0:20.07**  A gripper has two jobs: understand what it is touching, and react at once when the force is too high.

**0:26.61**  Software control loops add latency that varies: scheduling, communication, and inference time.

**0:33.63**  Here, the decision tree runs on a laptop. On the development host its walk averages 11.6 microseconds and peaked at 96.5, before any serial link delay.

> speech: Here, the decision tree runs on a laptop. On the development host its walk averages eleven point six microseconds, and peaked at ninety six point five, before any serial link delay.

**0:46.42**  So the work is split. The AI advises. Fixed hardware logic protects.

> speech: So the work is split. The A I advises. Fixed hardware logic protects.

**0:52.01**  The AI can only lower the command, never raise it, and the hard limits ignore it completely.

> speech: The A I can only lower the command, never raise it, and the hard limits ignore it completely.

## Scene 3 · SYSTEM ARCHITECTURE  (0:58.83 – 1:54.67)

**0:59.63**  A force sensor feeds a 12-bit AD7476A converter over SPI.

> speech: A force sensor feeds a twelve bit A D 7 4 7 6 A converter over S P I.

**1:05.52**  The ADC interface reads one 16-bit frame: four leading zeros, then twelve data bits.

> speech: The A D C interface reads one sixteen bit frame: four leading zeros, then twelve data bits.

**1:12.28**  Input conditioning registers the sample and flags invalid readings.

**1:16.74**  A fixed 256-entry lookup table turns force into a PWM duty command.

> speech: A fixed two hundred fifty six entry lookup table turns force into a P W M duty command.

**1:23.40**  The safety governor enforces the limits and can force a safe state.

**1:27.82**  The PWM generator drives the DRV8871 motor driver.

> speech: The P W M generator drives the D R V 8 8 7 1 motor driver.

**1:33.02**  A fault handler and the emergency stop feed the governor directly.

**1:37.36**  The advisory AI path arrives over UART, is integrity checked, and can only lower the command.

> speech: The advisory A I path arrives over you art, is integrity checked, and can only lower the command.

**1:43.48**  The target is a Terasic DE2-115 board at 50 megahertz. This is the prototype design; no physical validation is part of this work.

> speech: The target is a Terasic D E 2 115 board at 50 megahertz. This is the prototype design; no physical validation is part of this work.

## Scene 4 · HOW IT WORKS: THE RTL  (1:54.67 – 2:50.93)

**1:55.47**  In the ADC interface, a counter makes the SPI clock, samples on the falling edge, and shifts in sixteen bits. One frame takes 104 clock cycles: 2.08 microseconds.

> speech: In the A D C interface, a counter makes the S P I clock, samples on the falling edge, and shifts in sixteen bits. One frame takes 104 clock cycles: 2.08 microseconds.

**2:09.03**  A reading with a frame error, or at or above hex F F 0, is flagged invalid.

> speech: A reading with a frame error, or at or above hex F F zero, is flagged invalid.

**2:14.50**  The lookup table indexes on the top eight bits of the force code. No contact commands 180. The command ramps down to a hold level of 60, then to zero at the force limit.

**2:26.82**  The governor ORs every trip cause: force over limit, sensor fault, emergency stop, invalid reading, not yet armed, and predicted over-force. Any one forces the command to zero.

> speech: The governor ors every trip cause: force over limit, sensor fault, emergency stop, invalid reading, not yet armed, and predicted over-force. Any one forces the command to zero.

**2:39.55**  The PWM generator is a 12-bit counter: 12.2 kilohertz at 50 megahertz. The kill input forces the output low on the next clock.

> speech: The P W M generator is a twelve bit counter: 12.2 kilohertz at 50 megahertz. The kill input forces the output low on the next clock.

## Scene 5 · SAFETY DEMONSTRATIONS  (2:50.93 – 4:28.63)

**2:51.73**  First, the force limit. The AI claims a normal grip, but force jumps above the limit of 2560 counts. The governor enters the safe state, PWM goes low, and the AI is overridden.

> speech: First, the force limit. The A I claims a normal grip, but force jumps above the limit of 2560 counts. The governor enters the safe state, P W M goes low, and the A I is overridden.

**3:05.73**  Second, predictive trip. On a fast ramp the governor watches the rise per three millisecond window. In the RTL replay it tripped at a force code of 2015, twelve steps before the limit was crossed at 2569.

> speech: Second, predictive trip. On a fast ramp the governor watches the rise per three millisecond window. In the R T L replay it tripped at a force code of 2015, twelve steps before the limit was crossed at 2569.

**3:22.12**  The price is occasional early trips: on the simulated test episodes, 6.5 percent of episodes that never reached the limit still tripped early.

**3:31.89**  Third, hysteresis. After a trip the output stays inhibited until force falls below 2304. A force of 2304 still holds. 2303 releases.

**3:46.11**  Fourth, the emergency stop. Safe state rises in four clock cycles and PWM is low in five: 100 nanoseconds. It stays latched until an operator clears it.

> speech: Fourth, the emergency stop. Safe state rises in four clock cycles and P W M is low in five: 100 nanoseconds. It stays latched until an operator clears it.

**3:58.19**  Fifth, invalid sensor input. One corrupted ADC frame inhibits the drive for exactly one frame and latches nothing. Four consecutive bad frames latch a sensor fault until an operator clears it.

> speech: Fifth, invalid sensor input. One corrupted A D C frame inhibits the drive for exactly one frame and latches nothing. Four consecutive bad frames latch a sensor fault until an operator clears it.

**4:11.74**  If samples stop arriving, a watchdog raises the fault at 2000 clock cycles, which is 40 microseconds.

**4:19.49**  In every case the outcome is the same: PWM low, safe state asserted, and no recovery without the right conditions.

> speech: In every case the outcome is the same: P W M low, safe state asserted, and no recovery without the right conditions.

## Scene 6 · EXPERIMENTAL RESULTS  (4:28.63 – 6:12.07)

**4:29.43**  Now the evidence. All 175 directed checks across 12 testbenches pass in the existing RTL regression.

> speech: Now the evidence. All 175 directed checks across 12 testbenches pass in the existing R T L regression.

**4:38.12**  One thousand eight hundred test vectors were replayed through the RTL twice: once with the real decision tree, once with an AI that always claims normal grip. Both gave zero safe-state violations.

> speech: One thousand eight hundred test vectors were replayed through the R T L twice: once with the real decision tree, once with an A I that always claims normal grip. Both gave zero safe-state violations.

**4:50.70**  A separate experiment ran 15 scenarios and 159 checks. A software model met all 159. The RTL met 157; the two misses come from a stimulus that lasted about 240 ADC frames instead of one. A threshold-only baseline met 93, by design, because it has no hysteresis, fault, or stop handling.

> speech: A separate experiment ran 15 scenarios and 159 checks. A software model met all 159. The R T L met 157; the two misses come from a stimulus that lasted about 240 A D C frames instead of one. A threshold-only baseline met 93, by design, because it has no hysteresis, fault, or stop handling.

**5:16.69**  On a noisy crossing near the limit, the baseline toggled seven times. The hysteresis design inhibited once.

**5:23.93**  In simulation, a valid sample reaches PWM low in four clock cycles, 80 nanoseconds. An input change takes 105 to 192 cycles, mostly waiting for the next ADC frame.

> speech: In simulation, a valid sample reaches P W M low in four clock cycles, 80 nanoseconds. An input change takes 105 to 192 cycles, mostly waiting for the next A D C frame.

**5:38.28**  Frame by frame, 577 comparisons between the model and the RTL showed no differences.

> speech: Frame by frame, 577 comparisons between the model and the R T L showed no differences.

**5:45.83**  The decision tree reaches 91.9 percent accuracy on the simulated dataset, against 85.4 for a force-only baseline.

**5:54.97**  What this does not establish: physical safety. Inputs are synthetic, the ADC is a behavioural model, the AI dataset is simulated, 13 step-level model differences remain explained but not removed, and the Wokwi demonstration has not been run.

> speech: What this does not establish: physical safety. Inputs are synthetic, the A D C is a behavioural model, the A I dataset is simulated, 13 step-level model differences remain explained but not removed, and the Wokwi demonstration has not been run.

## Scene 7 · END-TO-END WORKFLOW  (6:12.07 – 6:31.03)

**6:12.87**  Putting it together. A valid ADC sample arrives.

> speech: Putting it together. A valid A D C sample arrives.

**6:16.73**  One clock cycle each: conditioning, lookup, governor, and PWM.

> speech: One clock cycle each: conditioning, lookup, governor, and P W M.

**6:22.31**  Four cycles later, if any limit is exceeded, the output is low. The AI can advise, but it cannot override.

> speech: Four cycles later, if any limit is exceeded, the output is low. The A I can advise, but it cannot override.

## Scene 8 · CLOSING  (6:31.03 – 7:05.67)

**6:31.83**  Tactile Reflex System.

**6:33.90**  An advisory-only AI, checked with an always-wrong AI. A slope-predictive pre-limit in plain hardware. A self-checking AI link. An instant PWM kill with a latched, fail-safe stop.

> speech: An advisory-only A I, checked with an always-wrong A I. A slope-predictive pre-limit in plain hardware. A self-checking A I link. An instant P W M kill with a latched, fail-safe stop.

**6:46.87**  These are design-level descriptions, not prior-art conclusions.

**6:51.24**  Proposed next steps, not done: Quartus synthesis and timing, board bring-up, recorded sensor data, and the Wokwi run.
