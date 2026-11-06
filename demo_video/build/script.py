"""Narration script. Each beat: caption (shown on screen) and optional speech override (for pronunciation).
All numbers are taken from the project evidence files (see demo_video/evidence_used.md)."""
import re
SCENES = [
 dict(id="s1", title="INTRODUCTION", beats=[
  ("Tactile Reflex System.", None),
  ("A deterministic, FPGA-based safety reflex for robotic gripping.", None),
  ("When a gripper squeezes too hard, the decision to stop must not wait for software.", None),
  ("Everything in this video is simulation. No physical hardware was tested.", None)]),
 dict(id="s2", title="THE PROBLEM", beats=[
  ("A gripper has two jobs: understand what it is touching, and react at once when the force is too high.", None),
  ("Software control loops add latency that varies: scheduling, communication, and inference time.", None),
  ("Here, the decision tree runs on a laptop. On the development host its walk averages 11.6 microseconds and peaked at 96.5, before any serial link delay.", "Here, the decision tree runs on a laptop. On the development host its walk averages eleven point six microseconds, and peaked at ninety six point five, before any serial link delay."),
  ("So the work is split. The AI advises. Fixed hardware logic protects.", None),
  ("The AI can only lower the command, never raise it, and the hard limits ignore it completely.", None)]),
 dict(id="s3", title="SYSTEM ARCHITECTURE", beats=[
  ("A force sensor feeds a 12-bit AD7476A converter over SPI.", None),
  ("The ADC interface reads one 16-bit frame: four leading zeros, then twelve data bits.", None),
  ("Input conditioning registers the sample and flags invalid readings.", None),
  ("A fixed 256-entry lookup table turns force into a PWM duty command.", None),
  ("The safety governor enforces the limits and can force a safe state.", None),
  ("The PWM generator drives the DRV8871 motor driver.", None),
  ("A fault handler and the emergency stop feed the governor directly.", None),
  ("The advisory AI path arrives over UART, is integrity checked, and can only lower the command.", None),
  ("The target is a Terasic DE2-115 board at 50 megahertz. This is the prototype design; no physical validation is part of this work.", None)]),
 dict(id="s4", title="HOW IT WORKS: THE RTL", beats=[
  ("In the ADC interface, a counter makes the SPI clock, samples on the falling edge, and shifts in sixteen bits. One frame takes 104 clock cycles: 2.08 microseconds.", None),
  ("A reading with a frame error, or at or above hex F F 0, is flagged invalid.", "A reading with a frame error, or at or above hex F F zero, is flagged invalid."),
  ("The lookup table indexes on the top eight bits of the force code. No contact commands 180. The command ramps down to a hold level of 60, then to zero at the force limit.", None),
  ("The governor ORs every trip cause: force over limit, sensor fault, emergency stop, invalid reading, not yet armed, and predicted over-force. Any one forces the command to zero.", None),
  ("The PWM generator is a 12-bit counter: 12.2 kilohertz at 50 megahertz. The kill input forces the output low on the next clock.", None)]),
 dict(id="s5", title="SAFETY DEMONSTRATIONS", beats=[
  ("First, the force limit. The AI claims a normal grip, but force jumps above the limit of 2560 counts. The governor enters the safe state, PWM goes low, and the AI is overridden.", None),
  ("Second, predictive trip. On a fast ramp the governor watches the rise per three millisecond window. In the RTL replay it tripped at a force code of 2015, twelve steps before the limit was crossed at 2569.", None),
  ("The price is occasional early trips: on the simulated test episodes, 6.5 percent of episodes that never reached the limit still tripped early.", None),
  ("Third, hysteresis. After a trip the output stays inhibited until force falls below 2304. A force of 2304 still holds. 2303 releases.", None),
  ("Fourth, the emergency stop. Safe state rises in four clock cycles and PWM is low in five: 100 nanoseconds. It stays latched until an operator clears it.", None),
  ("Fifth, invalid sensor input. One corrupted ADC frame inhibits the drive for exactly one frame and latches nothing. Four consecutive bad frames latch a sensor fault until an operator clears it.", None),
  ("If samples stop arriving, a watchdog raises the fault at 2000 clock cycles, which is 40 microseconds.", None),
  ("In every case the outcome is the same: PWM low, safe state asserted, and no recovery without the right conditions.", None)]),
 dict(id="s6", title="EXPERIMENTAL RESULTS", beats=[
  ("Now the evidence. All 175 directed checks across 12 testbenches pass in the existing RTL regression.", None),
  ("One thousand eight hundred test vectors were replayed through the RTL twice: once with the real decision tree, once with an AI that always claims normal grip. Both gave zero safe-state violations.", None),
  ("A separate experiment ran 15 scenarios and 159 checks. A software model met all 159. The RTL met 157; the two misses come from a stimulus that lasted about 240 ADC frames instead of one. A threshold-only baseline met 93, by design, because it has no hysteresis, fault, or stop handling.", None),
  ("On a noisy crossing near the limit, the baseline toggled seven times. The hysteresis design inhibited once.", None),
  ("In simulation, a valid sample reaches PWM low in four clock cycles, 80 nanoseconds. An input change takes 105 to 192 cycles, mostly waiting for the next ADC frame.", None),
  ("Frame by frame, 577 comparisons between the model and the RTL showed no differences.", None),
  ("The decision tree reaches 91.9 percent accuracy on the simulated dataset, against 85.4 for a force-only baseline.", None),
  ("What this does not establish: physical safety. Inputs are synthetic, the ADC is a behavioural model, the AI dataset is simulated, 13 step-level model differences remain explained but not removed, and the Wokwi demonstration has not been run.", None)]),
 dict(id="s7", title="END-TO-END WORKFLOW", beats=[
  ("Putting it together. A valid ADC sample arrives.", None),
  ("One clock cycle each: conditioning, lookup, governor, and PWM.", None),
  ("Four cycles later, if any limit is exceeded, the output is low. The AI can advise, but it cannot override.", None)]),
 dict(id="s8", title="CLOSING", beats=[
  ("Tactile Reflex System.", None),
  ("An advisory-only AI, checked with an always-wrong AI. A slope-predictive pre-limit in plain hardware. A self-checking AI link. An instant PWM kill with a latched, fail-safe stop.", None),
  ("These are design-level descriptions, not prior-art conclusions.", None),
  ("Proposed next steps, not done: Quartus synthesis and timing, board bring-up, recorded sensor data, and the Wokwi run.", None)]),
]
SPEECH = [(r"\bFPGA-based\b", "F P G A based"), (r"\bFPGA\b", "F P G A"), (r"\bADC\b", "A D C"), (r"\bPWM\b", "P W M"), (r"\bRTL\b", "R T L"), (r"\bSPI\b", "S P I"), (r"\bUART\b", "you art"),
          (r"\bAI\b", "A I"), (r"DRV8871", "D R V 8 8 7 1"), (r"AD7476A", "A D 7 4 7 6 A"), (r"DE2-115", "D E 2 115"), (r"\bOR[s]?\b", "ors"),
          (r"\bLUT\b", "lookup table"), (r"12-bit", "twelve bit"), (r"16-bit", "sixteen bit"), (r"256-entry", "two hundred fifty six entry"), (r"\bWokwi\b", "Wokwi"),
          (r"Quartus", "Quartus"), (r"\bms\b", "milliseconds"), (r"\bµs\b", "microseconds")]
def speech(cap, override):
    if override: s = override
    else:
        s = cap
    for pat, rep in SPEECH: s = re.sub(pat, rep, s)
    return s.replace("·", ",")
