// Tactile reflex controller CONCEPT MODEL on ESP32 (Wokwi). Separate software model, NOT the FPGA RTL.
// Boot: runs the scripted scenario suite once (structured CSV log on Serial, same lines as experiments/model_host.c).
// Then manual mode: potentiometer = force code (12-bit ADC), buttons = e-stop / fault clear, LEDs = status, PWM LED = drive command.
#include "scenarios.h"

#define PIN_POT    34
#define PIN_ESTOP  32   // pressed = low = e-stop (RTL estop_n = low). Not a fail-safe NC loop in this model.
#define PIN_CLEAR  33
#define PIN_RED    26   // safe_state / drive inhibited
#define PIN_GREEN  27   // normal
#define PIN_YELLOW 25   // sensor fault latched
#define PIN_PWM    18   // stands in for the DRV8871 input PWM; held low in safe state

static void emit(const char *l) { Serial.println(l); }

void setup() {
  Serial.begin(115200);
  pinMode(PIN_ESTOP, INPUT_PULLUP); pinMode(PIN_CLEAR, INPUT_PULLUP);
  pinMode(PIN_RED, OUTPUT); pinMode(PIN_GREEN, OUTPUT); pinMode(PIN_YELLOW, OUTPUT);
  ledcAttach(PIN_PWM, 5000, 8);
  Serial.println("# MODEL: software model of the documented controller concept; not the FPGA RTL");
  Serial.println("# LOG,scenario,step,t_us,code,present,frame_err,estop_n,fault_clear,safe,cmd,trip,baseline_safe,baseline_cmd,event");
  run_all_scenarios(emit);
  Serial.println("# SUITE DONE - manual mode: pot=force, buttons=e-stop/clear");
}

static rm_state st; static bool inited = false;
void loop() {
  if (!inited) { rm_reset(&st); inited = true; }
  rm_in in; in.code = analogRead(PIN_POT); in.present = 1; in.frame_err = 0;
  in.estop_n = digitalRead(PIN_ESTOP); in.fault_clear = !digitalRead(PIN_CLEAR);
  rm_out o = rm_step(&st, in);
  digitalWrite(PIN_RED, o.safe); digitalWrite(PIN_GREEN, !o.safe); digitalWrite(PIN_YELLOW, st.sensor_fault);
  ledcWrite(PIN_PWM, o.cmd);
  static uint32_t n = 0;
  if ((n++ % 50) == 0) { char b[96]; snprintf(b, sizeof b, "MAN,%lu,code=%u,safe=%d,cmd=%d,trip=%d", (unsigned long)millis(), in.code, o.safe, o.cmd, o.trip); Serial.println(b); }
  delay(SAMPLE_US / 1000 > 0 ? SAMPLE_US / 1000 : 1);
}
