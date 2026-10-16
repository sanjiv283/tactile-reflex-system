"""Build the 64-entry force->servo LUT from 3 parameters and write it as hex.

    python lut_gen.py --start 2000 --slope 16 --max 2000 -o lut_init.hex
    python lut_gen.py --test

Entry i covers ADC values 16*i .. 16*i+15. Value = servo pulse in microseconds.
The FPGA safety_governor clamps every value again in hardware; this check is
the software-side layer, so a bad table is rejected before it is ever sent.
"""
import argparse

N = 64
PULSE_MIN, PULSE_MAX = 1000, 2000   # must match safety_governor parameters


def make_lut(start, slope, p_max):
    return [max(PULSE_MIN, min(round(p_max), round(start - slope * i))) for i in range(N)]


def validate(lut):
    if len(lut) != N:
        raise ValueError(f"LUT needs {N} entries, got {len(lut)}")
    bad = [v for v in lut if not PULSE_MIN <= v <= PULSE_MAX]
    if bad:
        raise ValueError(f"entries outside {PULSE_MIN}-{PULSE_MAX} us: {bad[:5]}")
    if any(b > a for a, b in zip(lut, lut[1:])):
        raise ValueError("LUT must not tighten the grip as force increases")


def write_hex(lut, path):
    with open(path, "w") as f:
        f.writelines(f"{v:03x}\n" for v in lut)


def test():
    lut = make_lut(2000, 16, 2000)
    assert lut[0] == 2000 and lut[20] == 1680 and lut[63] == 1000
    validate(lut)
    # command-line values arrive as floats; entries must still be ints (write_hex formats them with :03x)
    flut = make_lut(2000.0, 16.0, 2000.0)
    assert flut == lut and all(type(v) is int for v in flut), "float arguments must give integer entries"
    assert make_lut(1900.0, 20.0, 1800.0)[0] == 1800 and type(make_lut(1900.0, 20.0, 1800.0)[0]) is int
    for bad in ([2100] * N, [1500] * 10 + [1600] * 54, [1500] * 63):
        try:
            validate(bad)
            raise AssertionError(f"should have rejected {bad[:3]}...")
        except ValueError:
            pass
    print("lut_gen self-test passed")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=float, default=2000, help="pulse at zero force (us)")
    ap.add_argument("--slope", type=float, default=16, help="us removed per force level")
    ap.add_argument("--max", type=float, default=2000, help="tightest allowed pulse (us)")
    ap.add_argument("-o", "--out", default="lut_init.hex")
    ap.add_argument("--test", action="store_true")
    a = ap.parse_args()
    if a.test:
        test()
    else:
        lut = make_lut(a.start, a.slope, a.max)
        validate(lut)
        write_hex(lut, a.out)
        print(f"wrote {a.out}: {lut[0]} us (no force) -> {lut[-1]} us (max force)")
