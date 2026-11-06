// scenarios.h - scripted force/e-stop/fault sequences and the scenario runner, shared by the Wokwi sketch and the host harness.
// Expectations are written from the documented rules (thresholds in reflex_model.h), not copied from model output.
#ifndef SCENARIOS_H
#define SCENARIOS_H
#include <stdio.h>
#include "reflex_model.h"

typedef struct {
    uint16_t n; int16_t c0, c1;            // n steps, force code ramps c0 -> c1 (constant if equal)
    uint8_t pres, ferr, es, fc;            // sample present, ADC frame error, estop_n, fault_clear
    int8_t noise;                          // +-noise counts from a fixed LFSR
    int8_t e_first, e_end, e_any;          // expected safe at first step / last step / at some step (-1 = not checked)
    int8_t e_mask, e_cmdnz;                // trip bits that must be set at last step / cmd nonzero (1) or zero (0) at last step
} seg_t;
typedef struct { const char *id, *desc; const seg_t *s; uint8_t n, stim; int8_t lead; } scen_t;
// lead: -1 not checked, 0 trip must not precede first sample >= FORCE_MAX, 1 trip must precede it

#define NSEG(a) ((uint8_t)(sizeof(a)/sizeof((a)[0])))
#define SEG(n,c0,c1,pr,fe,es,fc,nz,ef,ee,ea,em,ec) {n,c0,c1,pr,fe,es,fc,nz,ef,ee,ea,em,ec}
#define RUN(n,c0,c1,ef,ee,ea,em,ec) SEG(n,c0,c1,1,0,1,0,0,ef,ee,ea,em,ec)
#define HOLD(L) SEG(4,L,L,1,0,1,0,0,-1,1,-1,4,-1)     /* after reset: latched e-stop keeps safe state */
#define CLR(L)  SEG(3,L,L,1,0,1,1,0,-1,0,-1,-1,-1)    /* operator fault_clear */
#define PRE(L)  HOLD(L), CLR(L), RUN(14,L,L,-1,0,-1,-1,-1)   /* 3 segments, stimulus is segment 3 */

static const seg_t s01[] = { PRE(16), RUN(12,16,384,-1,0,-1,-1,1), RUN(12,384,1024,-1,0,-1,-1,1), RUN(12,1024,1500,-1,0,-1,-1,1), RUN(10,1500,1500,-1,0,0,-1,1) };
static const seg_t s02[] = { PRE(2200), RUN(63,2200,2700,-1,1,1,1,0) };
static const seg_t s03a[] = { PRE(2498), RUN(12,2558,2558,0,0,0,-1,1) };
static const seg_t s03b[] = { PRE(2499), RUN(12,2559,2559,0,0,0,-1,1) };
static const seg_t s03c[] = { PRE(2500), RUN(12,2560,2560,1,1,1,1,0) };
static const seg_t s03d[] = { PRE(2501), RUN(12,2561,2561,1,1,1,1,0) };
static const seg_t s03e[] = { PRE(2000), RUN(12,2559,2559,-1,0,1,-1,-1) };   /* big jump to a sub-limit value: predictor may trip transiently */
static const seg_t s04[]  = { PRE(2200), RUN(63,2200,2700,-1,1,1,1,0), RUN(24,2700,2400,-1,1,-1,1,0), RUN(12,2304,2304,-1,1,-1,1,0), RUN(12,2303,2303,0,0,-1,-1,1) };
static const seg_t s05[]  = { PRE(400), SEG(6,400,400,1,0,0,0,0,1,1,-1,4,0), SEG(6,400,400,1,0,1,0,0,-1,1,-1,4,0), CLR(400), RUN(6,400,400,-1,0,-1,-1,1) };
static const seg_t s06a[] = { PRE(400), SEG(1,400,400,1,1,1,0,0,1,1,-1,8,0), RUN(6,400,400,-1,0,-1,-1,1) };
static const seg_t s06b[] = { PRE(400), SEG(4,400,400,1,1,1,0,0,1,1,-1,8|2,0), RUN(6,400,400,-1,1,-1,2,0), CLR(400), RUN(6,400,400,-1,0,-1,-1,1) };
static const seg_t s06c[] = { PRE(400), SEG(4,400,400,0,0,1,0,0,-1,1,-1,2,0), RUN(6,400,400,-1,1,-1,2,0), CLR(400), RUN(6,400,400,-1,0,-1,-1,1) };
static const seg_t s06d[] = { PRE(400), RUN(6,4095,4095,1,1,1,8,0), RUN(3,400,400,-1,1,-1,2,0), CLR(400), RUN(6,400,400,-1,0,-1,-1,1) };
static const seg_t s07[]  = { PRE(2400), SEG(120,2500,2620,1,0,1,0,8,-1,-1,-1,-1,-1) };   /* noisy slow crossing: comparison with baseline */
static const seg_t s08[]  = { PRE(1000), RUN(40,1000,2800,-1,1,1,1,0) };                   /* fast ramp, ~277 counts/window */

static const scen_t SCENS[] = {
    {"S01_normal",        "no contact -> light -> grip -> high force below limit",   s01, NSEG(s01), 3, -1},
    {"S02_slow_crossing", "slow ramp through FORCE_MAX (~48 counts/window)",         s02, NSEG(s02), 3,  0},
    {"S03a_2558",         "hold 2558 (FORCE_MAX-2)",  s03a, NSEG(s03a), 3, -1},
    {"S03b_2559",         "hold 2559 (FORCE_MAX-1)",  s03b, NSEG(s03b), 3, -1},
    {"S03c_2560",         "hold 2560 (FORCE_MAX exactly)", s03c, NSEG(s03c), 3, -1},
    {"S03d_2561",         "hold 2561 (FORCE_MAX+1)",  s03d, NSEG(s03d), 3, -1},
    {"S03e_jump_2559",    "step 2000 -> 2559 (large rise, sub-limit target)", s03e, NSEG(s03e), 3, -1},
    {"S04_hysteresis",    "trip, then lower force through FORCE_REL (2304)",         s04, NSEG(s04), 3,  0},
    {"S05_estop",         "e-stop press, release (latched), operator clear",         s05, NSEG(s05), 3, -1},
    {"S06a_one_invalid",  "single invalid sample (below INVALID_LIMIT)",             s06a, NSEG(s06a), 3, -1},
    {"S06b_persist_invalid","4 consecutive invalid samples -> latched fault",        s06b, NSEG(s06b), 3, -1},
    {"S06c_dropout",      "sample dropout -> watchdog fault",                        s06c, NSEG(s06c), 3, -1},
    {"S06d_rail",         "railed ADC code 4095",                                    s06d, NSEG(s06d), 3, -1},
    {"S07_noisy_crossing","noisy slow crossing near FORCE_MAX (+-8 counts)",          s07, NSEG(s07), 3, -1},
    {"S08_fast_ramp",     "fast ramp (~277 counts/window): predictive pre-limit",     s08, NSEG(s08), 3,  1},
};
#define NSCENS (sizeof(SCENS)/sizeof(SCENS[0]))

typedef void (*emit_fn)(const char *line);

typedef struct { unsigned checks, passed, bpassed; } tally_t;
// One expectation: exp vs observed (model) and bobs (baseline). s0..s1 = step range the check refers to.
static inline void chk(emit_fn emit, tally_t *t, const char *id, int k, const char *kind, int exp, int obs, int bobs, unsigned s0, unsigned s1) {
    char b[200]; int ok = (obs == exp), bok = (bobs == exp);
    t->checks++; t->passed += ok; t->bpassed += bok;
    if (k >= 0) snprintf(b, sizeof b, "CHK,%s,%d,%s,%d,%d,%s,%d,%s,%u,%u", id, k, kind, exp, obs, ok ? "PASS" : "FAIL", bobs, bok ? "PASS" : "FAIL", s0, s1);
    else        snprintf(b, sizeof b, "CHK,%s,-,%s,%d,%d,%s,%d,%s,%u,%u", id, kind, exp, obs, ok ? "PASS" : "FAIL", bobs, bok ? "PASS" : "FAIL", s0, s1);
    emit(b);
}

static inline void run_all_scenarios(emit_fn emit) {
    char b[200]; unsigned i;
    snprintf(b, sizeof b, "PARAM,FORCE_MAX=%d,FORCE_REL=%d,PRED_K=%d,PRED_MIN_DELTA=%d,RAIL_HI=%d,INVALID_LIMIT=%d,SAMPLE_US=%d,PRED_WIN_STEPS=%d,WD_CLK=%d,FRAME_CLK=%d,SLOT_CLK=%d",
             FORCE_MAX, FORCE_REL, PRED_K, PRED_MIN_DELTA, RAIL_HI, INVALID_LIMIT, SAMPLE_US, PRED_WIN_STEPS, WD_CLK, FRAME_CLK, (int)(SLOT_CLK)); emit(b);
    for (i = 0; i < NSCENS; i++) {
        const scen_t *sc = &SCENS[i]; rm_state st; bl_state bl = {0}; rm_out o = {0,0,0}, bo = {0,0,0};
        int psafe = 1, pbsafe = 0, seen_over = 0, seen_safe = 0, bseen_safe = 0; uint16_t lfsr = 0xACE1u;
        unsigned step = 0, stim_start = 0, k, j, trans = 0, btrans = 0, first_over = 0, first_safe = 0, bfirst_safe = 0; tally_t t = {0, 0, 0};
        rm_reset(&st);
        for (j = 0; j < sc->stim; j++) stim_start += sc->s[j].n;
        for (k = 0; k < sc->n; k++) {
            const seg_t *g = &sc->s[k]; int any = 0, bany = 0, f_safe = 0, bf_safe = 0; unsigned n, s0 = step;
            for (n = 0; n < g->n; n++, step++) {
                rm_in in; int code = g->n > 1 ? g->c0 + (int)(((long)(g->c1 - g->c0) * n) / (g->n - 1)) : g->c0;
                if (g->noise) { lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u); code += (int)(lfsr % (2 * g->noise + 1)) - g->noise; }
                if (code < 0) code = 0;
                if (code > 4095) code = 4095;
                in.code = code; in.present = g->pres; in.frame_err = g->ferr; in.estop_n = g->es; in.fault_clear = g->fc;
                o = rm_step(&st, in); bo = bl_step(&bl, in);
                if (n == 0) { f_safe = o.safe; bf_safe = bo.safe; }
                if (step >= stim_start) {
                    if (o.safe != psafe) trans++;
                    if (bo.safe != pbsafe) btrans++;
                    if (!seen_over && code >= FORCE_MAX) { seen_over = 1; first_over = step; }
                    if (!seen_safe && o.safe) { seen_safe = 1; first_safe = step; }
                    if (!bseen_safe && bo.safe) { bseen_safe = 1; bfirst_safe = step; }
                }
                if (o.safe) any = 1;
                if (bo.safe) bany = 1;
                snprintf(b, sizeof b, "LOG,%s,%u,%lu,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s", sc->id, step, (unsigned long)step * SAMPLE_US, code,
                         in.present, in.frame_err, in.estop_n, in.fault_clear, o.safe, o.cmd, o.trip, bo.safe, bo.cmd,
                         step == 0 ? "reset" : o.safe != psafe ? (o.safe ? "safe_on" : "safe_off") : "");
                emit(b); psafe = o.safe; pbsafe = bo.safe;
            }
            if (g->e_first >= 0) chk(emit, &t, sc->id, k, "first_safe", g->e_first, f_safe, bf_safe, s0, s0);
            if (g->e_end >= 0)   chk(emit, &t, sc->id, k, "end_safe", g->e_end, o.safe, bo.safe, step - 1, step - 1);
            if (g->e_any >= 0)   chk(emit, &t, sc->id, k, "any_safe", g->e_any, any, bany, s0, step - 1);
            if (g->e_mask >= 0) {
                char kind[24]; snprintf(kind, sizeof kind, "trip_mask_%d", g->e_mask);
                chk(emit, &t, sc->id, k, kind, 1, (o.trip & g->e_mask) == g->e_mask, (bo.trip & g->e_mask) == g->e_mask, step - 1, step - 1);
            }
            if (g->e_cmdnz >= 0) chk(emit, &t, sc->id, k, "cmd_nonzero", g->e_cmdnz, o.cmd != 0, bo.cmd != 0, step - 1, step - 1);
        }
        if (sc->lead >= 0 && seen_over && seen_safe)
            chk(emit, &t, sc->id, -1, "trip_precedes_limit", sc->lead, first_safe < first_over, bseen_safe && bfirst_safe < first_over, 0, 0);
        snprintf(b, sizeof b, "SUM,%s,%s,%u,%u,%d,%d,%d,%u,%u,%u,%u", sc->id, t.passed == t.checks ? "PASS" : "FAIL", t.checks, t.passed,
                 seen_over ? (int)(first_over - stim_start) : -1, seen_safe ? (int)(first_safe - stim_start) : -1,
                 (seen_over && seen_safe) ? (int)first_safe - (int)first_over : 0, trans, btrans, t.bpassed, stim_start); emit(b);
    }
}
#endif
