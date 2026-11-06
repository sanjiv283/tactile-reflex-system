#!/bin/sh
# Formal checks (Yosys sat, free initial state). See tools/formal_check.py for what is PROVEN / BOUNDED / NOT ESTABLISHED. Exit 1 on any problem.
set -eu
cd "$(dirname "$0")/.."
python3 tools/formal_check.py
