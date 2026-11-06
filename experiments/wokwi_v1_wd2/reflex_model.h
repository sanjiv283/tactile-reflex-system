// reflex_model.h - SOFTWARE MODEL of the documented behaviour of rtl/input_conditioning.v, rtl/force_lut.v,
// rtl/fault_handler.v and rtl/safety_governor.v. This is NOT the RTL and is not proven equivalent to it.
// One rm_step() call = one ADC sample slot (SAMPLE_US of simulated time). Thresholds are the RTL defaults.
#ifndef REFLEX_MODEL_H
#define REFLEX_MODEL_H
#include <stdint.h>
#include "force_lut_table.h"

#define FORCE_MAX       2560   // safety_governor.v FORCE_MAX 12'hA00
#define FORCE_REL       2304   // safety_governor.v FORCE_REL 12'h900 (hysteresis release)
#define PRED_K          2      // safety_governor.v PRED_K
#define PRED_MIN_DELTA  150    // safety_governor.v PRED_MIN_DELTA
#define RAIL_HI         0xFF0  // input_conditioning.v RAIL_HI
#define INVALID_LIMIT   4      // fault_handler.v INVALID_LIMIT
// Model-only timing parameters (NOT the RTL values: RTL uses 150000-clk window, 2000-clk watchdog, 104-clk ADC frame)
#define SAMPLE_US       500
#define PRED_WIN_STEPS  6      // 3 ms window / SAMPLE_US, same 3 ms as RTL PRED_WIN at 50 MHz
#define WD_STEPS        2      // consecutive missing samples -> sensor fault

typedef struct { uint16_t code; uint8_t present, frame_err, estop_n, fault_clear; } rm_in;
typedef struct { uint8_t safe, cmd, trip; } rm_out;   // trip bits as RTL: 0 force, 1 sensor fault, 2 e-stop, 3 invalid ADC, 4 predicted
typedef struct {
    uint8_t armed, over, sensor_fault, estop, invalid, seeded, bad, wd, wcnt;
    uint16_t code, snap; int16_t delta;
} rm_state;

static const uint8_t rm_lut[256] = RM_LUT_INIT;

// Reset state mirrors the RTL: e-stop reads "pressed" during reset, so the latch needs an operator fault_clear.
static inline void rm_reset(rm_state *s) {
    s->armed = s->over = s->sensor_fault = s->invalid = s->seeded = s->bad = s->wd = s->wcnt = 0;
    s->estop = 1; s->code = s->snap = 0; s->delta = 0;
}

static inline rm_out rm_step(rm_state *s, rm_in in) {
    rm_out o;
    // fault_handler + input_conditioning
    if (in.present) s->wd = 0; else if (s->wd < WD_STEPS) s->wd++;
    if (in.present) {
        s->code = in.code;
        s->invalid = in.frame_err || in.code >= RAIL_HI;
        if (!s->invalid) s->bad = 0; else if (s->bad < INVALID_LIMIT) s->bad++;
    }
    if (s->wd >= WD_STEPS || s->bad >= INVALID_LIMIT) s->sensor_fault = 1; else if (in.fault_clear) s->sensor_fault = 0;
    if (!in.estop_n) s->estop = 1; else if (in.fault_clear) s->estop = 0;
    // safety_governor: slope window, hysteresis, trip
    if (in.present) {
        s->armed = 1;
        if (s->code >= FORCE_MAX) s->over = 1; else if (s->code < FORCE_REL) s->over = 0;
    }
    int pred = s->delta >= PRED_MIN_DELTA && (int)s->code + PRED_K * s->delta >= FORCE_MAX;
    o.trip = (s->over) | (s->sensor_fault << 1) | (s->estop << 2) | (s->invalid << 3) | (pred << 4);
    o.safe = o.trip || !s->armed;
    o.cmd = o.safe ? 0 : rm_lut[s->code >> 4];
    // window update last: as in the RTL, delta is registered and takes effect from the next sample
    if (++s->wcnt >= PRED_WIN_STEPS) {
        s->wcnt = 0;
        s->delta = s->seeded ? (int16_t)((int)s->code - (int)s->snap) : 0;
        s->snap = s->code; s->seeded = 1;
    }
    return o;
}

// BASELINE (defined before measuring): threshold-only controller. Inhibit iff the latest sample >= FORCE_MAX.
// No hysteresis, no latch, no prediction, no fault/e-stop handling, no armed-after-reset wait. Same LUT.
typedef struct { uint16_t code; } bl_state;
static inline rm_out bl_step(bl_state *b, rm_in in) {
    rm_out o;
    if (in.present) b->code = in.code;
    o.safe = b->code >= FORCE_MAX; o.trip = o.safe;
    o.cmd = o.safe ? 0 : rm_lut[b->code >> 4];
    return o;
}
#endif
