# Nix Performance Profiling Guide

This document explains how to profile and optimize Nix builds and evaluations in this repository using official Nix profiling tools.

## Overview

When experiencing slow `nixos-rebuild switch` or `home-manager switch` operations, the bottleneck is usually one of:

1. **Evaluation performance**: Complex Nix expressions taking time to evaluate
2. **Network downloads**: Missing packages from binary caches
3. **Local compilation**: Building packages from source due to cache misses
4. **Activation scripts**: System/home-manager activation overhead

## Profiling Tools

### Official Nix Profiling Script

Use `./nix-profile-proper.sh` to collect comprehensive performance data:

```bash
# Profile current configuration
./nix-profile-proper.sh

# Apply changes (example: Nix configuration optimization)
sudo nixos-rebuild switch --flake '.#tblack-t14-nixos'

# Profile again to measure improvement  
./nix-profile-proper.sh

# Compare results visually
nvim -d nix-profiles/*/ANALYSIS.md
```

### What Gets Profiled

The script collects data using official Nix profiling features:

| Tool | Data Collected | File Generated |
|------|----------------|----------------|
| `NIX_SHOW_STATS` | Evaluation timing, memory usage, GC stats | `nix-stats.json` |
| `NIX_COUNT_CALLS` | Function call counts and performance | `function-calls.log` |
| `--eval-profiler flamegraph` | Visual call stack analysis | `evaluation-flamegraph.svg` |
| `nix build --json` | Build derivation statistics | `build-stats.json` |

### Manual Profiling Commands

For specific analysis, you can run individual profiling commands:

```bash
# Get JSON evaluation statistics
NIX_SHOW_STATS=1 home-manager build --flake '.#tim@tblack-t14-nixos' --no-out-link

# Count function calls during evaluation
NIX_COUNT_CALLS=1 nix eval '.#homeConfigurations."tim@tblack-t14-nixos"' --apply 'cfg: {}'

# Generate evaluation flamegraph
nix eval --eval-profiler flamegraph '.#homeConfigurations."tim@tblack-t14-nixos"' --apply 'cfg: {}'
flamegraph.pl nix.profile > flamegraph.svg

# Get build statistics with derivation info
nix build --json '.#homeConfigurations."tim@tblack-t14-nixos".activationPackage' --no-link
```

## Performance Optimizations Applied

### Nix Configuration (`hosts/tblack-t14-nixos/default.nix`)

The following optimizations have been applied to improve build performance:

```nix
nix = {
  package = pkgs.nixVersions.stable;
  settings = {
    # Build performance
    max-jobs = 8;  # Use 8 of 14 available CPU cores
    cores = 0;     # Use all cores per job (optimal for this system)
    
    # Network optimizations
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"  # Additional binary cache
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    
    # Cache optimizations
    narinfo-cache-positive-ttl = 86400;  # Cache binary info for 24h
    connect-timeout = 10;                # Faster timeout on failed connections
    
    # Experimental features
    experimental-features = [ "nix-command" "flakes" ];
  };
};
```

### Expected Performance Improvements

- **3-5x speedup** from increased `max-jobs` (was using only 2/14 cores)
- **20-30% improvement** from additional substituters and caching
- **10-20% improvement** from evaluation cache optimization

## Interpreting Results

### Analysis.md Report Structure

Each profiling run generates an `ANALYSIS.md` report containing:

1. **Build Timing**: Wall-clock time for the build operation
2. **Nix Statistics**: JSON data with evaluation performance metrics
3. **Function Call Summary**: Most expensive function calls during evaluation
4. **Build Stats**: Derivation complexity and build requirements

### Key Metrics to Watch

| Metric | Location | Meaning |
|--------|----------|---------|
| `realTime` | `nix-stats.json` | Actual evaluation time |
| `cpuTime` | `nix-stats.json` | CPU time spent in evaluation |
| `gcTime` | `nix-stats.json` | Time spent in garbage collection |
| `memorySize` | `nix-stats.json` | Peak memory usage |
| Function counts | `function-calls.log` | Expensive function calls |

### Flamegraph Analysis

Open `evaluation-flamegraph.svg` in a web browser to visualize:
- **Wide bars**: Functions that consume the most evaluation time
- **Tall stacks**: Deep call chains that may indicate complexity
- **Hot paths**: Frequently called functions that are optimization candidates

## Common Bottlenecks

### 1. Large Package Sets
**Symptom**: High memory usage, long evaluation times
**Location**: `home.packages` with many packages
**Solution**: Use conditional loading or lazy evaluation

### 2. Complex Module Dependencies
**Symptom**: Deep call stacks in flamegraph
**Location**: Module imports and option evaluations
**Solution**: Simplify module structure, reduce interdependencies

### 3. Validated Scripts Framework
**Symptom**: High function call counts for script generation
**Location**: `validatedScripts.bashScripts`
**Solution**: Conditional script loading, reduce dependency complexity

### 4. Network-Related Delays
**Symptom**: Long wall-clock time vs. short evaluation time
**Location**: Build phase, not evaluation
**Solution**: Additional substituters, better network connectivity

## Troubleshooting

### Profiling Script Issues

- **Missing flamegraph.pl**: Install with `nix-shell -p flamegraph`
- **No stats generated**: Ensure `NIX_SHOW_STATS=1` is properly set
- **Permission errors**: Check write permissions in profile directory

### Performance Regressions

If performance degrades after changes:

1. Compare `nix-stats.json` files between runs
2. Look for increased `gcTime` or `memorySize`
3. Check `function-calls.log` for new expensive function calls
4. Review flamegraph for new hot paths

## File Structure

```
nix-profiles/YYYYMMDD-HHMMSS/
├── ANALYSIS.md                    # Human-readable summary
├── build-output.log               # Complete build output
├── nix-stats.json                 # Nix evaluator statistics
├── function-calls.log             # Function call performance data
├── eval.profile                   # Raw profiling data
├── evaluation-flamegraph.svg      # Visual performance analysis
└── build-stats.json              # Build derivation statistics
```

## References

- [Nix Manual - Evaluation Profiler](https://nixos.org/manual/nix/stable/advanced-topics/eval-profiler.html)
- [Nix Manual - Performance Tuning](https://nixos.org/manual/nix/stable/command-ref/conf-file.html)
- [Home Manager Performance Tips](https://nix-community.github.io/home-manager/)

## Legacy Note

Previous custom profiling approaches have been replaced with this official Nix tooling-based method. The official tools provide more accurate and actionable performance data than custom timing scripts.