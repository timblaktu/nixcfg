# Next Session: Interactive Mikrotik Configuration Design

**Context**: Mikrotik management skill v2.2.0 ready with local configuration design workflow (commit 4a3f1f9, 2026-01-28).

**Goal**: Guide me through interactive local configuration design workflow using the skill.

---

## Session Objectives

1. **Invoke skill and create initial configuration file**
   - Use `config_design_local` to generate a starting .rsc file
   - I'll specify the config name and base spec (L1.0, custom, or template)

2. **Iterative customization via natural language**
   - I'll request changes: "Add a bridge with IP x.x.x.x on ports 11-12"
   - You edit the .rsc file, show me what changed
   - Continue iterating based on my requests

3. **Final review with formatted output**
   - When I'm satisfied, print the complete configuration for visual confirmation
   - Format should match what I'd see from the remote switch (readable, organized)
   - **Important**: This requires you to read and display the .rsc file contents in a clean format

4. **Optional: Deploy to hardware**
   - If I confirm the config looks correct, guide me through deployment
   - Use `config_deploy_from_rsc` with dry-run first, then real deployment

---

## How to Guide This Session

### Step 1: Invoke Skill & Generate Initial Config

**Prompt me for**:
- Configuration name (e.g., "attic-network-v1")
- Base specification: "L1.0" (8-port flat network) | "custom" (blank) | path to template
- Any initial requirements (e.g., "L1.0 but with ports 1-4 only")

**Action**: Call `config_design_local` to create `~/.config/mikrotik/local-designs/<name>.rsc`

**Show me**:
- Path to created file
- Initial contents (use `cat` or Read tool)

---

### Step 2: Interactive Customization Loop

**My requests will be like**:
- "Add a bridge named bridge-office with IP 192.168.50.1/24 on ports ether11-ether12"
- "Add DHCP pool 192.168.50.100-200 for bridge-office"
- "Add DNS static entry office.local pointing to 192.168.50.10"
- "Change gateway IP to 192.168.50.254"
- "Remove ether8 from bridge-attic"

**Your workflow**:
1. **Read** the current .rsc file
2. **Edit** the .rsc file to implement my request
   - Use RouterOS scripting syntax (see skill SKILL.md Section 11 for examples)
   - Maintain proper structure (/interface bridge, /ip address, etc.)
3. **Show me a diff** or summary of what changed:
   ```diff
   + /interface bridge
   + add name=bridge-office comment="Office network"
   +
   + /interface bridge port
   + add bridge=bridge-office interface=ether11
   + add bridge=bridge-office interface=ether12
   ```
4. **Confirm** the change was made
5. **Wait for my next request** or confirmation to proceed

---

### Step 3: Print Configuration for Final Review

**When I say**: "Print the configuration" or "Show me the full config"

**Your action**:
1. Read the .rsc file
2. Display it in a clean, formatted way:
   - Use code block with `routeros` syntax highlighting
   - Include comments showing sections
   - Make it easy to visually scan

**Format example**:
```routeros
# ========================================
# RouterOS Configuration: attic-network-v1
# Generated: 2026-01-28
# ========================================

# Bridge Configuration
/interface bridge
add name=bridge-attic comment="L1.0 flat network"

# Bridge Ports
/interface bridge port
add bridge=bridge-attic interface=ether1
add bridge=bridge-attic interface=ether2
...

# IP Address Configuration
/ip address
add address=10.0.0.1/24 interface=bridge-attic comment="Gateway"

# DHCP Configuration
/ip pool
add name=dhcp-pool-attic ranges=10.0.0.100-10.0.0.200
...
```

**Optional enhancement**: You can also run `config_parse_rsc <file>` to show structured analysis

---

### Step 4: Optional Deployment

**If I'm satisfied and say**: "Deploy this to 192.168.88.1"

**Your workflow**:
1. **Dry-run first**:
   ```bash
   export DRY_RUN=1
   config_deploy_from_rsc "192.168.88.1" ~/.config/mikrotik/local-designs/<name>.rsc "replace"
   ```
   - Show me what would happen
   - Parse the config to show what will be deployed

2. **Confirm with me**: "This will reset the switch and deploy the new config. Proceed? (yes/no)"

3. **Real deployment** (if I confirm):
   ```bash
   export DRY_RUN=0
   config_deploy_from_rsc "192.168.88.1" ~/.config/mikrotik/local-designs/<name>.rsc "replace"
   ```

4. **Validate**: Run `validate_against_spec` if applicable, or `mikrotik_status` for generic check

---

## Important Notes

### .rsc File Format (RouterOS Scripting)
- Sections start with `/path/to/resource` (e.g., `/interface bridge`)
- Commands are `add`, `set`, `remove`, etc.
- Comments start with `#`
- Example:
  ```routeros
  /interface bridge
  add name=my-bridge comment="My bridge"

  /interface bridge port
  add bridge=my-bridge interface=ether1
  ```

### Skill Functions You'll Use
- `config_design_local(name, spec, [template])` - Generate initial .rsc
- `config_parse_rsc(file)` - Analyze .rsc structure
- `config_deploy_from_rsc(ip, file, mode)` - Deploy to device
- `mikrotik_status(ip)` - Quick status check
- `validate_against_spec(spec, ip)` - Validate deployment

### File Locations
- Local designs: `~/.config/mikrotik/local-designs/<name>.rsc`
- Templates: `~/.config/mikrotik/local-designs/templates/<name>.rsc`
- Device backups: `~/.config/mikrotik/192.168.88.1/backups/`
- Device exports: `~/.config/mikrotik/192.168.88.1/exports/`

### Editing .rsc Files
- You can use Edit tool to modify .rsc files directly
- Show me diffs or summaries after each edit
- .rsc files are just text - easy to version control with git

---

## Example Session Flow

**Me**: "Create a new configuration called attic-v2 based on L1.0 but with only ports 1-4"

**You**:
- Run `config_design_local "attic-v2" "L1.0"`
- Edit the .rsc to remove ether5-ether8 from bridge ports
- Show me the modified file

**Me**: "Add a second bridge called bridge-lab on ports 5-6 with IP 10.1.0.1/24"

**You**:
- Edit .rsc to add new bridge, ports, and IP
- Show me the diff:
  ```diff
  + /interface bridge
  + add name=bridge-lab comment="Lab network"
  +
  + /interface bridge port
  + add bridge=bridge-lab interface=ether5
  + add bridge=bridge-lab interface=ether6
  +
  + /ip address
  + add address=10.1.0.1/24 interface=bridge-lab comment="Lab gateway"
  ```

**Me**: "Print the configuration"

**You**: Display the complete .rsc file in formatted code block

**Me**: "Looks good, deploy to 192.168.88.1"

**You**: Run dry-run, confirm, then deploy (with my approval)

---

## Ready to Start?

Invoke the mikrotik-management skill and prompt me for:
1. Configuration name
2. Base specification (L1.0 / custom / template path)
3. Any initial customization requirements

Then guide me through the iterative design process!
