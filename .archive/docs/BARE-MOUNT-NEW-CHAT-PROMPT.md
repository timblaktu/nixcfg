# New Chat Prompt: WSL Bare Mount GitHub Issue & PR Documentation

## Context
I've developed a NixOS-WSL module for declaratively configuring WSL bare disk mounts. The implementation is complete and tested. I need to create a GitHub issue that describes the problem this solves, and refactor the existing PR description to reference that issue.

## Current Files
- `BARE-MOUNT-PR.md` - Current PR description (needs refactoring to reference issue)
- Module implementation: `/home/tim/src/NixOS-WSL/modules/wsl-bare-mount.nix`
- My configuration using it: `/home/tim/src/nixcfg/hosts/thinky-nixos/default.nix`

## Tasks

### Task 1: Generate GitHub Issue Documentation
Create `./BARE-MOUNT-ISSUE.md` with content suitable for a NixOS-WSL GitHub issue that:
- Describes the problem from a user perspective
- Explains use cases where current WSL storage options cause problems
- Documents the performance impact (9P is 10x+ slower)
- Shows current workarounds and why they're insufficient
- Proposes declarative configuration as the solution
- Includes examples of what users currently have to do manually

### Task 2: Refactor PR Description
Update `./BARE-MOUNT-PR.md` to:
- Reference the issue by placeholder link (e.g., "Fixes #XXX")
- Remove redundant problem description (since it's in the issue)
- Focus primarily on the technical solution
- Keep implementation details, testing, and technical constraints
- Maintain usage examples and integration options

## Key Points to Emphasize in Issue
- WSL's 9P filesystem causes 10x+ performance penalties for `/mnt/c` access
- Users with ext4/btrfs/ZFS disks must manually run `wsl --mount --bare` before each session
- No declarative way to configure these mounts in NixOS
- Breaks NixOS philosophy of declarative configuration
- Particularly painful for Nix store operations on large repos

## Structure for Issue
1. Problem description (user-facing pain points)
2. Current workarounds and their limitations
3. Use cases (Nix store, ZFS pools, shared data, etc.)
4. Proposed solution (declarative module)
5. Example of desired configuration

Please help me create these two documents with the issue providing comprehensive problem context and the PR focusing on the solution implementation.