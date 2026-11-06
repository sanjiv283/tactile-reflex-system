#!/usr/bin/env python3
"""Deterministic host->RTL link vectors, built with host/ai_host.build_ai_packet (the code that talks to the board).
tb/host_link_bytes.mem : the byte stream, 3 bytes per group.   tb/host_link_expect.mem : one byte per group,
{accepted[7], 0, 0, valid[4], 0, 0, class[1:0]} = what the RTL must do with that group."""
import os, sys, random
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "host")); sys.path.insert(0, os.path.join(ROOT, "ml"))
from ai_host import build_ai_packet

def vectors():
    g = []   # (bytes, accepted, cls, valid)
    for cls in range(4):
        for valid in (True, False): g.append((build_ai_packet(cls, valid), True, cls, valid))
    rnd = random.Random(2026)
    for _ in range(24):
        cls, valid = rnd.randrange(4), rnd.random() < 0.7; g.append((build_ai_packet(cls, valid), True, cls, valid))
    for cls in range(4):                                         # corrupted groups: must be ignored entirely
        p = bytearray(build_ai_packet(cls)); q = bytearray(p); q[2] ^= 0x01; g.append((bytes(q), False, cls, True))     # bad complement
        q = bytearray(p); q[0] = 0xA4; g.append((bytes(q), False, cls, True))                                          # wrong header
        q = bytearray(p); q[2] = p[1]; g.append((bytes(q), False, cls, True))                                          # complement not inverted
        g.append((build_ai_packet(cls), True, cls, True))                                                              # and a good one right after
    return g

def write(root=ROOT):
    g = vectors()
    with open(os.path.join(root, "tb", "host_link_bytes.mem"), "w") as fh:
        for b, *_ in g: fh.write("\n".join("%02X" % x for x in b) + "\n")
    with open(os.path.join(root, "tb", "host_link_expect.mem"), "w") as fh:
        for b, acc, cls, valid in g: fh.write("%02X\n" % ((int(acc) << 7) | (int(valid) << 4) | cls))
    return len(g)

if __name__ == "__main__": print(write(), "groups")
