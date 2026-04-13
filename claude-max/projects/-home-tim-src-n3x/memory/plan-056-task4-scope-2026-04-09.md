---
name: Plan 056 Task 4 (NVMe builders) scope + inventory 2026-04-09
description: All design decisions locked for NVMe instance-store builders migration; ready to implement
type: project
---

Plan 056 Task 4 scope fully decided 2026-04-09. Ready for implementation session.

**Why:** do_image_tar (220s jetson) and do_unpack are IO-bound on gp3 EBS. Moving builds_dir + yocto cache to instance-store NVMe is the next big win after Tasks 2/3 landed (83bbfe9).

**How to apply:** Next session executes the locked implementation TODO — do not re-litigate scope unless user raises new info.

## Decisions locked
- **Option B**: builds_dir + yocto BOTH on instance-store NVMe
- **Tier**: c7g.2xlarge → c7gd.2xlarge, c6i.2xlarge → c6id.2xlarge (1×474GB NVMe, same vCPU/RAM)
- **Destructive OK**: destroy vol-0c88c2c693c30fc62 (graviton 300G yocto) + vol-004c793e0029c329d (x86 200G yocto) on redeploy
- **Never-stop policy**: loud Pulumi comment; CloudWatch StoppedInstance alarm optional followup
- **Coldsnap-for-instance-store**: impossible (no API surface). Accept cold first pipeline post-redeploy. Donor-EBS-seed pattern on backlog if redeploy frequency increases.
- **/nix ZFS 500G EBS**: UNCHANGED (must persist)

## Cost delta (monthly, net)
- graviton: +$3 (−$24 EBS, +$27 instance)
- x86: +$51 (−$16 EBS, +$67 instance)

## Current inventory (2026-04-09, both runners)
Current design: 3 EBS volumes per runner — 50G root, 200/300G yocto, 500G ZFS for /nix. No instance store today (nvme naming is EBS-NVMe interface).

**x86 i-05babf9452225b071 (ami-0eeecc7488dce44cf):**
- root 9.9G/49G (22%); gitlab-runner builds=5.6G
- yocto 26G/197G (13%, vol-004c793e0029c329d)
- /nix ZFS 22G/471G (5%)

**graviton i-0ce7a68655a1ecd08 (ami-002a36d5b92657424):**
- root 29G/49G (60% ⚠); gitlab-runner builds=24G, journal=8M, logs=9.1M
- yocto 104G/295G (37%, vol-0c88c2c693c30fc62)
- /nix ZFS 127G/471G (27%)

## Q5/F2 root cause — CONFIRMED
Graviton root FS pressure is **100% /var/lib/gitlab-runner/builds** (24G of 25G /var). Zero contribution from journal, logs, or other /var state. NVMe relocation fully resolves F2 — no separate investigation needed.

## Sizing fit on 474GB NVMe (graviton worst case)
104G yocto + ~100G peak builds = ~200G. 274G headroom. ✅

## Baseline for measurement (pipeline 2941962, commit 7cde2a8)
jetson 535s, converix 462s, amd-v3c18i 154s, qemuarm64 351s (concurrent with jetson).
Expected wins in do_unpack + do_image_tar. First post-deploy pipeline will be SLOW (cold yocto) — expected, not a regression.

## Instance-type data (gathered from AWS 2026-04-09)
- c7gd.2xlarge: 8vCPU/16GB/1×474GB NVMe (+$27/mo vs c7g)
- c6id.2xlarge: 8vCPU/16GB/1×474GB NVMe (+$67/mo vs c6i)
- c7gd.4xlarge: 16vCPU/32GB/1×950GB NVMe (~+$345/mo — rejected as out of scope)
- c6id.4xlarge: 16vCPU/32GB/1×950GB NVMe (~+$390/mo — rejected)
- No 2-disk option at relevant tiers (starts at metal / i-family)

## Unrelated findings this session
- **publish-vte-qemu{amd,arm}64-qcow2 jobs FAIL** on our ec2-graviton shell runner: upstream `automation/virtualrack/vm-builder` `.publish_vm` template assumes Alpine executor (`apk add --no-cache jq`). Not our bug to fix; user said ignore VTE. Record here so we don't re-trigger and re-diagnose.
