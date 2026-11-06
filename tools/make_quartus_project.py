#!/usr/bin/env python3
"""Generate a Quartus Prime project (DE2-115, Cyclone IV E EP4CE115F29C7) into quartus_build/ (git-ignored). Quartus is NOT installed in the
development environment: this only PREPARES the project; compiling, timing closure and programming are untested (see HARDWARE_VALIDATION_GUIDE).

  python3 tools/make_quartus_project.py --pins constraints/de2_115_from_reference.qsf --reference DE2_115.qsf   # pins must pass tools/check_pins.py --strict
  python3 tools/make_quartus_project.py --allow-unverified-pins                             # prepare for a synthesis-only trial; banner says NOT FOR PROGRAMMING
Then, on a machine with Quartus:  cd quartus_build && quartus_sh --flow compile tactile_reflex   (reports in quartus_build/output_files)"""
import argparse, glob, os, shutil, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = "de2_115_top"

def build(out, pins, allow_unverified, reference=None):
    rtl = sorted(glob.glob(os.path.join(ROOT, "rtl", "*.v")))
    if not rtl or not os.path.exists(os.path.join(ROOT, "rtl", "force_lut.mem")): raise SystemExit("rtl/ or rtl/force_lut.mem missing (run tools/gen_lut.py)")
    pin_text = ""
    if pins:
        with open(pins) as fh: pin_text = fh.read()
    verified = False
    if pins:
        import tempfile
        with tempfile.TemporaryDirectory() as td:                       # validate BEFORE creating the output directory (a refused run must leave nothing behind)
            cmd = [sys.executable, os.path.join(ROOT, "tools", "check_pins.py"), "--qsf", pins, "--strict", "--json", os.path.join(td, "pin_check.json")] + (["--reference", reference] if reference else [])
            r = subprocess.run(cmd, capture_output=True, text=True)
        verified = r.returncode == 0 and "VERIFIED AGAINST REFERENCE" in r.stdout   # strict passes only with a reference; without one it fails
        if not verified and not allow_unverified: raise SystemExit("pin file not verified (tools/check_pins.py --reference ... --strict fails):\n" + r.stdout)
    elif not allow_unverified: raise SystemExit("no --pins file; use --allow-unverified-pins for a synthesis-only trial")
    os.makedirs(os.path.join(out, "rtl"), exist_ok=True)       # only now that every check has passed
    for f in rtl + [os.path.join(ROOT, "rtl", "force_lut.mem")]: shutil.copy(f, os.path.join(out, "rtl", os.path.basename(f)))   # mem file resolves relative to the project
    shutil.copy(os.path.join(ROOT, "constraints", "de2_115.sdc"), os.path.join(out, "de2_115.sdc"))
    banner = "# PIN FILE VERIFIED AGAINST A SUPPLIED TERASIC REFERENCE (tools/check_pins.py)\n" if verified else "# !!! PINS NOT VERIFIED - FOR A SYNTHESIS-ONLY TRIAL, NOT FOR PROGRAMMING A BOARD !!!\n"
    qsf = [banner, "set_global_assignment -name FAMILY \"Cyclone IV E\"", "set_global_assignment -name DEVICE EP4CE115F29C7", f"set_global_assignment -name TOP_LEVEL_ENTITY {TOP}",
           "set_global_assignment -name STRATIX_DEVICE_IO_STANDARD \"3.3-V LVTTL\"", "set_global_assignment -name SDC_FILE de2_115.sdc"]
    qsf += [f"set_global_assignment -name VERILOG_FILE rtl/{os.path.basename(f)}" for f in rtl]
    qsf += ["", pin_text if pin_text else "# no pin assignments (synthesis-only trial)"]
    with open(os.path.join(out, "tactile_reflex.qsf"), "w") as fh: fh.write("\n".join(qsf) + "\n")
    with open(os.path.join(out, "tactile_reflex.qpf"), "w") as fh: fh.write('PROJECT_REVISION = "tactile_reflex"\n')
    return verified, [os.path.basename(f) for f in rtl]

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "quartus_build")); ap.add_argument("--pins"); ap.add_argument("--reference", help="Terasic DE2_115.qsf used to verify --pins"); ap.add_argument("--allow-unverified-pins", action="store_true")
    a = ap.parse_args()
    v, files = build(a.out, a.pins, a.allow_unverified_pins, a.reference)
    print(f"prepared {a.out}: {len(files)} RTL files, pins {'VERIFIED' if v else 'NOT VERIFIED'}; Quartus not run (BLOCKED: not installed)")
