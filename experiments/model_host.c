// Host harness: runs the same scenario runner as the Wokwi sketch and prints the log to stdout.
// First verifies the model's LUT table against rtl/force_lut.mem (path in argv[1]).
#include <stdio.h>
#include <stdlib.h>
#include "wokwi/scenarios.h"
static void emit(const char *l) { puts(l); }
int main(int argc, char **argv) {
    if (argc > 1) {
        FILE *f = fopen(argv[1], "r"); unsigned v; int i = 0;
        if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
        while (i < 256 && fscanf(f, "%x", &v) == 1) { if (rm_lut[i] != v) { fprintf(stderr, "LUT mismatch at %d\n", i); return 1; } i++; }
        fclose(f); if (i != 256) { fprintf(stderr, "LUT file short\n"); return 1; }
    }
    run_all_scenarios(emit);
    return 0;
}
