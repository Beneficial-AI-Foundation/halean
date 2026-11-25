#!/usr/bin/env bash
# Build the HALean library and every executable inside a cgroup-v1 memory group capped at 16 GiB.
# Usage: review/experiments/01-build-axioms/build.sh   (from the repository root, as root)
set -u
export PATH=$HOME/.elan/bin:$PATH
CG=/sys/fs/cgroup/memory/halean-build
mkdir -p $CG
echo $((16*1024*1024*1024)) > $CG/memory.limit_in_bytes
echo 0 > $CG/memory.max_usage_in_bytes 2>/dev/null || true
echo $$ > $CG/cgroup.procs
L=review/experiments/01-build-axioms/logs
echo "limit_in_bytes=$(cat $CG/memory.limit_in_bytes)" > $L/memcap.txt
lean --version > $L/toolchain.txt; lake --version >> $L/toolchain.txt
start=$(date +%s)
lake build HALean > $L/build-lib.log 2>&1; echo "exit=$?" >> $L/build-lib.log
lake build halean-automation halean-script halean-template halean-sun-grid halean-core halean-core-states halean-core-services halean-core-events halean-helpers > $L/build-exe.log 2>&1; echo "exit=$?" >> $L/build-exe.log
end=$(date +%s)
echo "wall_seconds=$((end-start))" >> $L/memcap.txt
echo "max_usage_in_bytes=$(cat $CG/memory.max_usage_in_bytes)" >> $L/memcap.txt
echo "failcnt=$(cat $CG/memory.failcnt)" >> $L/memcap.txt
