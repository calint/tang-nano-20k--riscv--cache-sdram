#!/bin/sh
set -e
cd $(dirname "$0")

NUM_TESTS=8

for i in 1 3; do
    ./testbench.sh $i 2>&1 | grep -v -E \
        "passed|readmemh|VCD|finish|prim_tsim|sorry: constant selects in always|Case unique/unique0 qualities are ignored"
done
