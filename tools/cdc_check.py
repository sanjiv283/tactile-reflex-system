#!/usr/bin/env python3
"""Structural clock-domain-crossing check (text based; NOT a substitute for a commercial CDC tool, no MTBF).
It follows EVERY input of the boundary modules (default: de2_115_top and tactile_reflex_top) through the module hierarchy and requires each use to be a
recognised synchroniser:
   * two-flop shift capture            X <= {X[0], in};   with X declared [1:0] and X read only as X[1]
   * two-stage register chain          A <= in;  B <= A;  with A read only by that second statement
   * async-assert / sync-release reset  always @(posedge clk or negedge in) sr <= {sr[..], 1'b1}   (only this one pattern may use an asynchronous reset)
   * a connection to a child module port that is itself a synchroniser (checked recursively)
   * a clock (used in posedge / wired to child clocks)
Any other use of an input (combinational logic, a direct flop, an unrecognised statement) is a VIOLATION, so a newly added asynchronous input cannot pass silently.
An input bit that nothing reads is reported as 'unused'. Also: no other asynchronous-reset flop, one clock. Usage: python3 tools/cdc_check.py [--rtl DIR] [--roots a,b]. Exit 1 on a violation."""
import argparse, glob, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ID = lambda n: r"(?<![\.\w])%s\b" % n
def strip(t): return re.sub(r"/\*.*?\*/", "", re.sub(r"//[^\n]*", "", t), flags=re.S)
def load(rtl):
    mods = {}
    for f in sorted(glob.glob(os.path.join(rtl, "*.v"))):
        with open(f) as fh: t = strip(fh.read())
        for m in re.finditer(r"\bmodule\s+(\w+)\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;(.*?)\bendmodule", t, re.S):
            hdr, body = m.group(2), m.group(3)
            ports = {}
            for p in re.finditer(r"\b(input|output|inout)\s+(?:wire\s+|reg\s+)*(?:\[([^\]]+)\]\s*)?(\w+)", hdr): ports[p.group(3)] = (p.group(1), p.group(2))
            mods[m.group(1)] = dict(file=os.path.basename(f), ports=ports, body=body)
    return mods
def balanced(s, i):
    d = 0
    for j in range(i, len(s)):
        d += s[j] == "("; d -= s[j] == ")"
        if d == 0: return j
    return len(s) - 1
def instances(mod, mods):
    out = []; body = mod["body"]
    for m in re.finditer(r"\b(\w+)\s*(?:#\s*\()?", body):
        name = m.group(1)
        if name not in mods: continue
        i = m.end() - 1 if body[m.end() - 1] == "(" else m.end()
        if body[m.start():m.end()].rstrip().endswith("("):                 # skip the parameter list #( ... )
            j = balanced(body, body.index("(", m.start())); i = j + 1
        k = re.match(r"\s*(\w+)\s*\(", body[i:])
        if not k: continue
        o = i + k.end() - 1; c = balanced(body, o); conns = {}
        for p in re.finditer(r"\.(\w+)\s*\(", body[o + 1:c]):
            s = o + 1 + p.end() - 1; e = balanced(body, s); conns[p.group(1)] = body[s + 1:e]
        out.append((name, k.group(1), conns))
    return out
def sync_status(mods, mname, port, seen=()):
    """-> (kind, detail) kind in sync|clock|unused|BAD"""
    if (mname, port) in seen: return ("BAD", "recursive")
    seen = seen + ((mname, port),); mod = mods[mname]; body = mod["body"]
    if re.search(r"posedge\s+%s\b" % port, body) and not re.search(r"negedge\s+%s\b" % port, body): return ("clock", "")
    uses = list(re.finditer(ID(port), body))
    if not uses: return ("unused", "")
    notes = []; kinds = []
    for name, inst, conns in instances(mod, mods):
        for cp, expr in conns.items():
            if re.search(ID(port), expr):
                if cp not in mods[name]["ports"]: return ("BAD", f"{inst}.{cp} is not a port of {name}")
                k, d = sync_status(mods, name, cp, seen)
                if k not in ("sync", "clock"): return ("BAD", f"feeds {name}.{cp} ({inst}) which is {k}: {d}")
                notes.append(f"-> {name}.{cp}: {d or k}"); kinds.append(k)
    stmts = [s for s in re.split(r";", body) if re.search(ID(port), s)]
    for s in stmts:
        im = re.match(r"\s*(\w+)\s*(?:#\s*\(.*?\)\s*)?\w+\s*\(", s, re.S)
        if im and im.group(1) in mods: continue                       # an instance: handled through its connections
        sh = re.search(r"(\w+)\s*<=\s*\{\s*\1\s*\[0\]\s*,\s*%s\s*\}" % port, s)
        ch = re.search(r"(\w+)\s*<=\s*%s\s*$" % port, s.strip()) if not sh else None
        ar = re.search(r"always\s*@\s*\(\s*posedge\s+\w+\s+or\s+negedge\s+%s\s*\)" % port, s)
        if sh:
            X = sh.group(1); decl = re.search(r"reg\s*\[1:0\][^;]*\b%s\b" % X, body)
            rest = re.sub(r"\breg\b[^;]*;", "", body.replace(sh.group(0), ""))
            rest = re.sub(r"\b%s\s*\[1\]" % X, "", re.sub(r"\b%s\s*<=\s*[^;{]*;" % X, ";", rest))     # reset assignments (constants) are writes, not reads
            if not decl: return ("BAD", f"{X} is not a 2-bit register")
            if re.search(r"\b%s\b" % X, rest): return ("BAD", f"capture register {X} is read other than as {X}[1]")
            notes.append(f"2-FF shift {X}"); continue
        if ch:
            A = ch.group(1)
            readers = [t for t in re.split(r";", re.sub(r"\breg\b[^;]*;", ";", body)) if re.search(r"\b%s\b" % A, t) and not re.search(r"\b%s\s*<=\s*%s\b" % (A, port), t) and not re.search(r"\b%s\s*<=\s*[\d']" % A, t)]
            if not (len(readers) == 1 and re.search(r"(\w+)\s*<=\s*%s\s*$" % A, readers[0].strip())): return ("BAD", f"first stage {A} is not read only by a second register stage")
            notes.append(f"2-stage chain {A}"); continue
        if ar:
            blk = re.search(r"if\s*\(\s*!\s*%s\s*\)\s*(\w+)\s*<=\s*[^;]*;\s*else\s*\1\s*<=\s*\{\s*\1\s*\[[^\]]*\]\s*,\s*1'b1\s*\}" % port, body + ";")
            alt = re.search(r"if\s*\(\s*!\s*%s\s*\)\s*(\w+)\s*<=[^;]*;\s*else\s+\1\s*<=\s*\{\s*\1\s*\[[^\]]*\]\s*,\s*1'b1\s*\}" % port, body)
            if blk or alt: notes.append("async-assert / sync-release reset chain"); continue
        decl_only = re.fullmatch(r"\s*(input|output|wire|reg)\b[^;=]*", s)
        if decl_only: continue
        return ("BAD", "unrecognised use: " + re.sub(r"\s+", " ", s.strip())[:110])
    if kinds and all(k == "clock" for k in kinds) and len(notes) == len(kinds): return ("clock", "")
    return ("sync", "; ".join(notes))

def bits(mods, name):
    out = []
    for p, (d, w) in mods[name]["ports"].items():
        if d != "input": continue
        if w: hi, lo = [int(x) for x in re.findall(r"\d+", w)[:2]]; out += [(p, i) for i in range(lo, hi + 1)]
        else: out.append((p, None))
    return out
def check(rtl, roots):
    mods = load(rtl); viol = []; report = []
    for r in roots:
        if r not in mods: viol.append(f"root module {r} not found"); continue
        for p, i in bits(mods, r):
            kind, det = sync_status(mods, r, p)
            if i is not None:                                         # vector: a bit nobody reads is 'unused'
                reads = re.findall(r"\b%s\s*\[(\d+)\]" % p, mods[r]["body"]); whole = re.search(r"\b%s\b(?!\s*\[)" % p, mods[r]["body"])
                if kind == "sync" and not whole and str(i) not in reads: kind, det = "unused", ""
            report.append((r, p if i is None else f"{p}[{i}]", kind, det))
            if kind == "BAD": viol.append(f"{r}.{p if i is None else f'{p}[{i}]'}: {det}")
    # only recognised async-reset synchronisers may use an asynchronous reset; one clock
    for n, m in mods.items():
        for e in re.finditer(r"always\s*@\s*\(([^)]*)\)", m["body"]):
            ev = e.group(1)
            if re.search(r"\bnegedge\b|\bposedge\s+\w+\s+or\b", ev):
                port = re.search(r"negedge\s+(\w+)", ev)
                if not (port and sync_status(mods, n, port.group(1))[0] == "sync"): viol.append(f"{n}: asynchronous-reset block '{ev}' is not a recognised reset synchroniser")
            if re.search(r"posedge\s+(\w+)", ev) and not re.search(r"posedge\s+(clk|CLOCK_50)\b", ev) and "negedge" not in ev: viol.append(f"{n}: unexpected clock '{ev}'")
    return mods, report, viol
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rtl", default=os.path.join(ROOT, "rtl")); ap.add_argument("--roots", default="de2_115_top,tactile_reflex_top"); ap.add_argument("-v", action="store_true")
    a = ap.parse_args(argv); mods, rep, viol = check(a.rtl, a.roots.split(","))
    n_sync = sum(1 for r in rep if r[2] == "sync"); n_un = [f"{r[0]}.{r[1]}" for r in rep if r[2] == "unused"]
    print(f"CDC structural check: {len(rep)} boundary input bits in {a.roots}; {n_sync} synchronised, {sum(1 for r in rep if r[2]=='clock')} clock, unused: {', '.join(n_un) or 'none'} -> " + ("OK" if not viol else f"{len(viol)} VIOLATION(S)"))
    if a.v:
        for r in rep: print(f"  {r[0]}.{r[1]:14s} {r[2]:6s} {r[3]}")
    for v in viol: print("  VIOLATION:", v)
    return 1 if viol else 0
if __name__ == "__main__": sys.exit(main())
