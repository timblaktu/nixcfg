# NixOS-WSL Bare Mount Feature - Pull Request Summary

## Performance Investigation Results

After extensive testing with a Samsung 990 PRO 4TB NVMe on WSL2, we've discovered important performance characteristics of WSL bare mounts:

### Key Finding: Block Size Scaling Issue

The performance gap between .vhdx and bare mount storage is due to WSL2's bare mount I/O path implementation, not filesystem or mount options:

| Block Size | VHDX Performance | Bare Mount Performance | Gap |
|------------|------------------|------------------------|-----|
| 4KB | 74.7 MB/s | 76.0 MB/s | Equal |
| 64KB | 1.0 GB/s | 722 MB/s | -28% |
| 1MB | 4.1 GB/s | 1.2 GB/s | -71% |
| 16MB | 6.0 GB/s | 1.1 GB/s | -82% |

### What We Tested
- **Mount Options**: `nobarrier`, `lazytime`, `nodiratime`, `discard`, various stripe sizes
- **Kernel Tuning**: Read-ahead buffer, I/O scheduler changes
- **Filesystem**: Non-journaled ext4 (optimal for performance)
- **Result**: Mount options provided minimal improvement (2.3-2.5 GB/s vs 4.6 GB/s for vhdx)

### Why This Doesn't Invalidate the Feature

Despite current I/O path limitations in WSL2, bare mounts provide significant value:

1. **I/O Distribution**: Spread load across multiple physical disks
2. **Storage Management**: Bypass .vhdx size constraints (256GB default, 1TB max)
3. **Predictable Performance**: No variable cache behavior or memory pressure effects
4. **Dedicated Resources**: Isolate workloads from OS disk contention
5. **Future Improvement**: Microsoft may optimize the bare mount I/O path in future WSL2 updates

### Module Implementation Quality

- ✅ **Clean NixOS module** following all conventions
- ✅ **PowerShell script generation** for Windows-side mounting
- ✅ **SystemD integration** with validation services
- ✅ **Comprehensive documentation** and examples
- ✅ **Production tested** on real hardware

### Recommended PR Approach

1. **Be transparent** about current performance characteristics
2. **Emphasize** the real benefits (I/O distribution, storage flexibility)
3. **Document** that performance limitations are in WSL2, not the module
4. **Include** optimization recommendations for users:
   ```nix
   # Optimal mount options for non-journaled ext4
   options = [ "noatime" "nobarrier" "lazytime" ];
   ```

### PR Description Template

```markdown
## Add WSL bare mount support for direct disk access

This PR adds the `wsl.bareMounts` module to enable declarative configuration of WSL bare disk mounts, providing direct block device access and storage management flexibility.

### Features
- Declarative NixOS configuration for multiple bare mounts
- PowerShell script generation for Windows-side mounting
- SystemD mount units with boot-time validation
- UUID-based disk identification for reliability

### Use Cases
- Distribute I/O load across multiple physical disks
- Bypass .vhdx size limitations for large datasets
- Dedicated storage for databases, build caches, or data processing
- Predictable performance without virtualization layer caching

### Performance Note
Current WSL2 bare mount implementation shows reduced throughput compared to .vhdx storage for large sequential I/O (see benchmarks in docs). This is a WSL2 limitation, not a module issue. Bare mounts still provide value through I/O distribution and storage flexibility.

### Testing
- ✅ Tested on Samsung 990 PRO 4TB NVMe
- ✅ SystemD services validated
- ✅ Mount persistence across reboots
- ✅ Performance characteristics documented

Fixes #[issue-number]
```

## Next Steps

1. Create PR at: https://github.com/nix-community/NixOS-WSL/compare
2. Reference this investigation in PR documentation
3. Be prepared to discuss performance findings with maintainers
4. Consider opening WSL2 issue about bare mount I/O scaling
