#!/usr/bin/env python3
"""Reference force->pulse table (same formula as rtl/lut_engine.v). Writes lut.mem for $readmemh."""
with open("lut.mem", "w") as f:
    for adc in range(1024):
        f.write("%03x\n" % (2000 - adc))
print("wrote lut.mem (1024 entries, pulse_us = 2000 - adc)")
