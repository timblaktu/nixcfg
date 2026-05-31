# Plan 030: tmux System Monitoring Dashboard

## Motivation

Build a comprehensive tmux-based system monitoring dashboard for observing system
activity during intensive builds, tests, and other resource-heavy operations. Replace
the current single-pane htop setup with a multi-pane, multi-tool dashboard that covers
CPU/memory, disk I/O, network, and (optionally) GPU monitoring.

Key design principle: **decouple data collection from display** where possible, so
monitoring data persists beyond the viewing session and supports forensic analysis.

## Research Summary

Evaluated 20+ CLI monitoring tools against these criteria:
- tmux pane compatibility
- Decoupled polling/collection from display/view
- Available in nixpkgs
- Performance and flexibility
- Configurability

### Tool Selection

**Tier 1 (Core Dashboard)**:

| Category | Tool | nixpkg | HM Module | Decoupled |
|---|---|---|---|---|
| Primary overview | btop | `btop` (1.4.6) | `programs.btop` | No |
| Per-process network | bandwhich | `bandwhich` (0.23.1) | No | No |
| Device disk I/O | iostat | `sysstat` (12.7.7) | No | Yes (sadc/sar) |
| Per-process disk I/O | iotop-c | `iotop-c` (1.31) | No | No |
| GPU | nvtop | `nvtopPackages.full` (3.3.2) | No | No |
| Historical forensics | below | `below` (0.11.0) | No | Yes (record/replay/dump) |
| Network diagnostics | trippy | `trippy` (0.13.0) | No | No |

**Tier 2 (Add as needed)**:

| Tool | nixpkg | Purpose |
|---|---|---|
| gping | `gping` (1.20.1) | Ping with ASCII graph |
| nload | `nload` (0.7.4) | Per-interface bandwidth graph |
| dool | `dool` (1.3.8) | CPU+disk+net correlator |
| zenith | `zenith` (0.14.3) | Zoomable historical charts |
| iftop | `iftop` (1.0pre4) | Per-connection bandwidth |
| atop | `atop` (2.12.1) | Recording daemon + replay |

**tmux Orchestration**: `tmuxp` (1.67.0) — YAML session definitions.

### Decoupled Architecture Stack

```
below record (systemd service, persistent)
    → below replay (TUI, on-demand)
    → below dump --format json/csv/openmetrics (scripting)

sadc (systemd timer, persistent)
    → sar -d/-n/-r/-u (historical CLI, on-demand)

Optional: node_exporter → Prometheus → grafterm (terminal Prometheus dashboards)
```

## Tasks

| # | Task | Status | DoD |
|---|------|--------|-----|
| T1 | Add monitoring packages to home-manager config | `TASK:COMPLETE` | All Tier 1 + tmuxp packages added to home.packages, btop configured via programs.btop module. `home-manager switch` succeeds. |
| T2 | Configure btop with build-monitoring optimized settings | `TASK:COMPLETE` | Custom btop config: gruvbox theme, iowait on CPU lower graph, 2s update interval, shown_boxes tuned for build monitoring (cpu mem net proc disk). Verify config loads. |
| T3 | Create tmuxp YAML for monitoring dashboard | `TASK:COMPLETE` | YAML session definition with 3 windows: overview (btop + bandwhich), io (iostat + iotop-c), network (nload + gping). Layout adapts to terminal size. `tmuxp load monitor` works. |
| T4 | Set up below recording daemon | `TASK:COMPLETE` | systemd service for `below record` with 7-day retention, 5s interval, compression. Opt-in (WSL2 eBPF uncertain). |
| T5 | Set up sysstat data collection | `TASK:COMPLETE` | sadc timer (1-minute interval), daily cleanup of old data, tmpfiles rule for /var/log/sa. Opt-in. |
| T6 | Create shell alias/script for dashboard launch | `TASK:COMPLETE` | `monitor` writeShellApplication that creates or attaches to tmuxp session. Capabilities-based wrappers for bandwhich/iotop-c/trippy. |
| T7 | Add Tier 2 packages and test | `TASK:COMPLETE` | Tier 2 (gping, nload, dool, iftop) gated by `enableTier2` option. Extra tmuxp window added when enabled. |
| T8 | Document the monitoring setup | `TASK:COMPLETE` | Comprehensive module header comment: features, quick start, WSL2 caveats, usage examples. |

## Architecture Context

### tmuxp Layout (Draft)

```
Window 1: "overview"
┌──────────────────────────────────────────┐
│                  btop                     │ (60% height)
│                                          │
├─────────────────────┬────────────────────┤
│     bandwhich       │    nload           │ (40% height)
│ (per-process net)   │ (interface bw)     │
└─────────────────────┴────────────────────┘

Window 2: "io"
┌──────────────────────────────────────────┐
│        iostat -xz 2                      │ (50% height)
│                                          │
├──────────────────────────────────────────┤
│        iotop-c                           │ (50% height)
│                                          │
└──────────────────────────────────────────┘

Window 3: "network"
┌──────────────────────────────────────────┐
│        trippy / gping                    │ (50% height)
│                                          │
├──────────────────────────────────────────┤
│        iftop / dool                      │ (50% height)
│                                          │
└──────────────────────────────────────────┘
```

### Home Manager Config (Draft)

```nix
# In home-manager config
programs.btop = {
  enable = true;
  settings = {
    color_theme = "gruvbox_dark";
    theme_background = false;
    update_ms = 2000;
    proc_sorting = "cpu lazy";
    shown_boxes = "cpu mem net proc";
    cpu_graph_lower = "iowait";
    disk_io_mode = true;
  };
};

home.packages = with pkgs; [
  # Tier 1
  bottom bandwhich sysstat iotop-c
  nvtopPackages.full below trippy
  # Tier 2
  gping nload dool iftop
  # Orchestration
  tmuxp
];
```

### Capability/Sudo Considerations

Several tools need root or NET_ADMIN:
- `bandwhich` — needs NET_ADMIN or root
- `iotop-c` — needs root (reads /proc/*/io)
- `below record` — needs root (eBPF, cgroup access)

Options:
1. Passwordless sudo for specific binaries (sudoers.d)
2. Linux capabilities (`setcap cap_net_admin+ep /path/to/bandwhich`)
3. Run entire tmux session as root (not recommended)

Preferred: capabilities where possible, passwordless sudo for the rest.
