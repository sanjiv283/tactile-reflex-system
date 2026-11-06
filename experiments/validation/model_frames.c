// Runs the software model on a per-frame stimulus file (one hex word per step, same layout as tb_frames.v, sample always present).
// Compile against a COPY of reflex_model.h whose PRED_WIN_STEPS is changed (see run_validation.py).
#include <stdio.h>
#include "reflex_model.h"
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "r"); unsigned w; int k = 0; rm_state s; rm_reset(&s);
    while (f && fscanf(f, "%x", &w) == 1) {
        rm_in in = { (uint16_t)(w & 0xFFF), (uint8_t)!((w >> 12) & 1), (w >> 13) & 1, (w >> 14) & 1, (w >> 15) & 1 };
        rm_out o = rm_step(&s, in);
        printf("FRM,%s,%d,%d,%d,%d,%d,%d\n", argv[2], k++, o.safe, o.cmd, o.trip, s.sensor_fault, s.estop);
    }
    return 0;
}
