#!/usr/bin/env python3
"""Force-sensor calibration -> recommended FORCE_MAX / FORCE_REL (ADC counts). Works ONLY on measurements you supply; it never invents data.

CSV columns (header required):  trial,direction,mass_g,adc
    trial      any label for one loading event          direction  up (adding load) | down (removing load; optional, enables the hysteresis estimate)
    mass_g     calibrated mass resting on the sensor    adc        raw 12-bit counts read through the real signal chain (0..4095)
Usage:  python3 tools/calibrate.py --data calib.csv --limit-n 20 [--margin-sigma 3] [--out results/calibration_report.json]
        python3 tools/calibrate.py --make-template calib_template.csv
Rule: FORCE_MAX = counts(limit) - margin_sigma*sigma(repeatability) - hysteresis/2 - 1 LSB-quantisation, so the trip happens AT OR BEFORE the limit with the stated margin;
      FORCE_REL = FORCE_MAX - max(hysteresis, 4*sigma, 5% of the used range, 32).  The report is data, not a safety case: review it, then change the RTL parameters yourself."""
import argparse, csv, json, os, sys
import numpy as np
G = 9.80665; RAIL_HI = 0xFF0

class CalError(Exception): pass

def load(path):
    with open(path, newline="") as fh:
        rd = csv.DictReader(fh)
        if rd.fieldnames is None or [c.strip() for c in rd.fieldnames] != ["trial", "direction", "mass_g", "adc"]: raise CalError(f"header must be exactly trial,direction,mass_g,adc (got {rd.fieldnames})")
        rows = list(rd)
    out = []
    for i, r in enumerate(rows, 2):
        try: m, a = float(r["mass_g"]), float(r["adc"])
        except ValueError: raise CalError(f"line {i}: non-numeric mass_g/adc")
        d = r["direction"].strip().lower()
        if d not in ("up", "down"): raise CalError(f"line {i}: direction must be up or down")
        if not (np.isfinite(m) and np.isfinite(a)) or m < 0: raise CalError(f"line {i}: invalid mass/adc")
        if not 0 <= a <= 4095: raise CalError(f"line {i}: adc {a} outside 0..4095")
        out.append((r["trial"], d, m, a))
    return out

def analyse(rows, limit_n, margin_sigma=3.0):
    masses = sorted({m for _, d, m, _ in rows if d == "up"})
    if len(masses) < 5: raise CalError(f"need at least 5 distinct loads in the 'up' data (got {len(masses)})")
    up = {m: np.array([a for _, d, mm, a in rows if d == "up" and mm == m]) for m in masses}
    for m, v in up.items():
        if len(v) < 3: raise CalError(f"load {m} g has only {len(v)} 'up' readings (need >= 3 for a repeatability estimate)")
    mean = np.array([up[m].mean() for m in masses]); std = np.array([up[m].std(ddof=1) for m in masses]); force = np.array(masses) * 1e-3 * G
    viol = [(masses[i], masses[i + 1]) for i in range(len(masses) - 1) if mean[i + 1] < mean[i] - 2 * max(std[i], std[i + 1], 1.0)]
    if viol: raise CalError(f"curve is not monotonic beyond noise between loads {viol}: check wiring / sensor seating")
    if np.max(force) < limit_n: raise CalError(f"largest calibration load {np.max(force):.2f} N is below the requested limit {limit_n} N: the limit would be an extrapolation")
    sat = [m for m in masses if np.any(up[m] >= RAIL_HI)]
    mean_m = np.maximum.accumulate(mean)                     # enforce non-decreasing for interpolation
    counts_at = lambda F: float(np.interp(F, force, mean_m))
    sig_at = lambda F: float(np.interp(F, force, std))
    c_lim = counts_at(limit_n); sigma = max(sig_at(limit_n), float(std.max()) * 0.0)
    down_m = sorted({m for _, d, m, _ in rows if d == "down"}); hyst = 0.0; hyst_pts = []
    for m in down_m:
        if m in up:
            dv = np.array([a for _, d, mm, a in rows if d == "down" and mm == m]); h = abs(float(dv.mean() - up[m].mean())); hyst_pts.append((m, h)); hyst = max(hyst, h)
    used = float(mean_m[-1] - mean_m[0])
    fmax = int(np.floor(c_lim - margin_sigma * sigma - hyst / 2 - 1))
    frel = int(np.floor(fmax - max(hyst, 4 * sigma, 0.05 * used, 32)))
    j = int(np.searchsorted(force, limit_n)); j = min(max(j, 1), len(force) - 1)
    slope = (mean_m[j] - mean_m[j - 1]) / (force[j] - force[j - 1]) if force[j] != force[j - 1] else float("nan")
    warn = []
    if sat: warn.append(f"ADC reaches the rail (>= {RAIL_HI}) at load(s) {sat} g: the RTL treats that as invalid")
    if fmax >= RAIL_HI - 80: warn.append("FORCE_MAX is within 80 counts of the rail: the sensor saturates near the limit, choose a more sensitive divider")
    if fmax <= 0 or frel <= 0: warn.append("computed thresholds are not positive: noise/hysteresis too large for this limit")
    if not np.isnan(slope) and slope < 5: warn.append(f"sensitivity at the limit is only {slope:.1f} counts/N")
    if not down_m: warn.append("no 'down' data: hysteresis assumed 0, FORCE_REL uses the noise/range floor only")
    return dict(units="ADC counts", g=G, limit_n=limit_n, margin_sigma=margin_sigma, loads_g=masses, mean_counts=[round(float(x), 2) for x in mean], std_counts=[round(float(x), 2) for x in std],
                readings_per_load=[len(up[m]) for m in masses], counts_at_limit=round(c_lim, 2), sigma_at_limit=round(sigma, 3), hysteresis_counts=round(hyst, 2),
                repeatability_pct_of_range=round(100 * float(std.max()) / used, 3) if used else None, sensitivity_counts_per_N_at_limit=None if np.isnan(slope) else round(float(slope), 2),
                recommended=dict(FORCE_MAX=fmax, FORCE_REL=frel, hex=dict(FORCE_MAX="12'h%03X" % fmax if fmax > 0 else None, FORCE_REL="12'h%03X" % frel if frel > 0 else None)),
                current_rtl=dict(FORCE_MAX=2560, FORCE_REL=2304), warnings=warn,
                note="Derived only from the supplied measurements. Apply by editing the RTL parameters and re-running the regression; this tool changes nothing.")

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data"); ap.add_argument("--limit-n", type=float); ap.add_argument("--margin-sigma", type=float, default=3.0)
    ap.add_argument("--out", default="results/calibration_report.json"); ap.add_argument("--make-template")
    a = ap.parse_args(argv)
    if a.make_template:
        with open(a.make_template, "w", newline="") as fh: fh.write("trial,direction,mass_g,adc\n")
        print("wrote header-only template", a.make_template); return 0
    if not a.data or a.limit_n is None: ap.print_help(); return 0
    try: rep = analyse(load(a.data), a.limit_n, a.margin_sigma)
    except CalError as e: print("CALIBRATION DATA ERROR:", e, file=sys.stderr); return 2
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as fh: json.dump(rep, fh, indent=1)
    r = rep["recommended"]; print(f"recommended FORCE_MAX={r['FORCE_MAX']} FORCE_REL={r['FORCE_REL']} (current RTL 2560/2304); counts at limit {rep['counts_at_limit']}, sigma {rep['sigma_at_limit']}, hysteresis {rep['hysteresis_counts']}")
    for w in rep["warnings"]: print("  WARNING:", w)
    return 0

if __name__ == "__main__": sys.exit(main())
