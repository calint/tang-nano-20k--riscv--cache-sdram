#!/bin/sh
set -e
cd $(dirname "$0")

NUM_TESTS=8

for i in 1 3; do
    echo -n "test $i: "
    ./testbench.sh $i 2>&1 | grep -E \
        "PASSED|FATAL"
done
