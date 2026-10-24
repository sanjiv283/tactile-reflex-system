"""Generate rtl/force_lut.mem: 256 entries, index = force_code[11:4], value = PWM duty (0-255).
No contact: full approach drive. Ramps down through light contact to a hold level, then to 0 at FORCE_MAX (idx 160)."""
def duty(i):
    if i < 8:   return 180
    if i < 96:  return round(180 - (i - 8) * (180 - 60) / (96 - 8))
    if i < 160: return round(60 - (i - 96) * 60 / (160 - 96))
    return 0
if __name__ == "__main__":
    open("rtl/force_lut.mem", "w").write("".join(f"{duty(i):02X}\n" for i in range(256)))
    print("wrote rtl/force_lut.mem")
