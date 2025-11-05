#!/usr/bin/env bash
#
# stress.sh - convenience wrapper for usefule stress-ng invocations
#
# Purpose:
#   This script wraps common stress-ng scenarios into callable bash functions.
#   You can source this file into your shell or scripts and directly run
#   various CPU, memory, disk, and mixed load stress tests.
#
# Usage:
#   source $HOME/bin/stress.sh
#   cpu_max_all_60s
#   mem_random_burst
#
# Requirements:
#   stress-ng must be installed and available in PATH.
#
# ------------------------------------------------------------------------
# Cheat Sheet Reference (from integrated guide)
#
#   CPU:
#     cpu_max_all_60s               # Max CPU load all cores, 60s
#     cpu_50pct_4workers_30s        # 50% load on 4 workers, 30s
#     cpu_sequential_120s           # Stress each CPU sequentially, 120s
#     cpu_random_loads              # Random per-core loads
#
#   Memory:
#     mem_fixed_1Gx2_60s             # 1GB on 2 VM workers, 60s
#     mem_95pct_5workers_60s         # 95% RAM split across 5 workers, 60s
#     mem_random_burst               # Random memory allocations, bursts
#
#   Disk / I/O:
#     disk_basic_2workers_60s        # Disk stress, 2 workers, 60s
#     disk_io_combined_60s           # Disk + I/O, 2 workers each, 60s
#     io_random_burst                # Random I/O worker bursts
#
#   Mixed / Random:
#     all_subsystems_120s            # 1 worker per stressor, 120s
#     random_4stressors_60s          # 4 random stressors, 60s
#     mixed_random_burst             # Random stressors, small bursts
#
# ------------------------------------------------------------------------

## -------------------------
## 1. CPU Stress
## -------------------------

cpu_max_all_60s() {
    stress-ng --cpu 0 --timeout 60s --metrics-brief
}

cpu_50pct_4workers_30s() {
    stress-ng --cpu 4 --cpu-load 50 --timeout 30s --metrics-brief
}

cpu_sequential_120s() {
    stress-ng --cpu 0 --sequential --timeout 120s
}

cpu_random_loads() {
    for _ in {1..4}; do
        stress-ng --cpu 1 --cpu-load "$(shuf -i 10-90 -n 1)" --timeout 10s &
    done
    wait
}

## -------------------------
## 2. Memory Stress
## -------------------------

mem_fixed_1Gx2_60s() {
    stress-ng --vm 2 --vm-bytes 1G --timeout 60s --metrics-brief
}

mem_95pct_5workers_60s() {
    stress-ng --vm 5 --vm-bytes 95% --timeout 60s --metrics-brief
}

mem_random_burst() {
    for _ in {1..3}; do
        stress-ng --vm 1 --vm-bytes "$(shuf -i 100-800 -n 1)M" --timeout 10s &
    done
    wait
}

## -------------------------
## 3. Disk and I/O Stress
## -------------------------

disk_basic_2workers_60s() {
    stress-ng --disk 2 --timeout 60s --metrics-brief
}

disk_io_combined_60s() {
    stress-ng --disk 2 --io 2 --timeout 60s --metrics-brief
}

io_random_burst() {
    for _ in {1..5}; do
        stress-ng --io "$(shuf -i 1-4 -n 1)" --timeout 5s &
    done
    wait
}

## -------------------------
## 4. Mixed / Random Stress
## -------------------------

all_subsystems_120s() {
    stress-ng --all 1 --timeout 120s --metrics-brief
}

random_4stressors_60s() {
    stress-ng --random 4 --timeout 60s --metrics-brief
}

mixed_random_burst() {
    for _ in {1..3}; do
        stress-ng --random "$(shuf -i 1-6 -n 1)" --timeout 15s --metrics-brief &
    done
    wait
}

# Helper to list all available functions
stressng_help() {
    grep -E '^\w+\(\)' "${BASH_SOURCE[0]}" | cut -d '(' -f1 | sort
}

# EOF
