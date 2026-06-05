#!/usr/bin/env bash
# mikrotik-status.sh - Compact status display for Mikrotik RouterOS switch
# Usage: ./mikrotik-status.sh [host] [user]
# Default: host=192.168.88.1, user=admin
set -euo pipefail

HOST="${1:-192.168.88.1}"
USER="${2:-admin}"

ssh_exec() {
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${USER}@${HOST}" "$1" 2>/dev/null
}

# Test connectivity
if ! ssh_exec "/system resource print" >/dev/null; then
    echo "Switch: OFFLINE (cannot reach $HOST)"
    exit 1
fi

# System info
model=$(ssh_exec "/system routerboard get model" || echo "Unknown")
version=$(ssh_exec "/system resource get version" || echo "Unknown")
uptime=$(ssh_exec "/system resource get uptime" || echo "Unknown")
echo "Switch: $model (RouterOS $version, uptime $uptime)"

# Bridges
bridge_count=$(ssh_exec "/interface bridge print count-only" || echo "0")
if [ "$bridge_count" = "0" ]; then
    echo "+-- Bridge: Not configured"
    exit 0
fi

bridges=$(ssh_exec "/interface bridge print terse")
echo "$bridges" | while IFS= read -r line; do
    name=$(echo "$line" | sed -n 's/.*name=\([^ ]*\).*/\1/p')
    [ -z "$name" ] && continue
    vlan_filtering=$(echo "$line" | sed -n 's/.*vlan-filtering=\([^ ]*\).*/\1/p')

    echo "+-- Bridge: $name"
    echo "    +-- VLAN Filtering: ${vlan_filtering:-unknown}"

    # Ports
    port_count=$(ssh_exec "/interface bridge port print count-only where bridge=$name" || echo "0")
    echo "    +-- Ports: $port_count active"
    if [ "$port_count" != "0" ]; then
        ports=$(ssh_exec "/interface bridge port print terse where bridge=$name")
        echo "$ports" | while IFS= read -r pline; do
            iface=$(echo "$pline" | sed -n 's/.*interface=\([^ ]*\).*/\1/p')
            comment=$(echo "$pline" | sed -n 's/.*comment=\([^"]*\).*/\1/p')
            [ -z "$iface" ] && continue
            if [ -n "$comment" ]; then
                echo "    |   +-- $iface ($comment)"
            else
                echo "    |   +-- $iface"
            fi
        done
    fi

    # IP
    ip_info=$(ssh_exec "/ip address print terse where interface=$name")
    if [ -n "$ip_info" ]; then
        echo "$ip_info" | while IFS= read -r iline; do
            addr=$(echo "$iline" | sed -n 's/.*address=\([^ ]*\).*/\1/p')
            [ -z "$addr" ] && continue
            echo "    +-- IP: $addr"
        done
    else
        echo "    +-- IP: Not configured"
    fi

    # DHCP
    dhcp_count=$(ssh_exec "/ip dhcp-server print count-only where interface=$name" || echo "0")
    if [ "$dhcp_count" = "0" ]; then
        echo "    +-- DHCP: Not configured"
    else
        dhcp_info=$(ssh_exec "/ip dhcp-server print terse where interface=$name")
        echo "$dhcp_info" | while IFS= read -r dline; do
            dname=$(echo "$dline" | sed -n 's/.*name=\([^ ]*\).*/\1/p')
            pool=$(echo "$dline" | sed -n 's/.*address-pool=\([^ ]*\).*/\1/p')
            [ -z "$dname" ] && continue
            pool_range=$(ssh_exec "/ip pool get $pool ranges" || echo "unknown")
            active=$(ssh_exec "/ip dhcp-server lease print count-only where server=$dname and status=bound" || echo "0")
            static=$(ssh_exec "/ip dhcp-server lease print count-only where server=$dname and dynamic=no" || echo "0")
            echo "    +-- DHCP: $dname"
            echo "    |   +-- Pool: $pool_range"
            echo "    |   +-- Active Leases: $active"
            echo "    |   +-- Static Leases: $static"
        done
    fi

    # DNS (global)
    dns_servers=$(ssh_exec "/ip dns get servers" || echo "")
    if [ -z "$dns_servers" ]; then
        echo "    +-- DNS: Not configured"
    else
        echo "    +-- DNS: $dns_servers"
        static_count=$(ssh_exec "/ip dns static print count-only" || echo "0")
        if [ "$static_count" != "0" ]; then
            static_entries=$(ssh_exec "/ip dns static print terse")
            echo "$static_entries" | while IFS= read -r sline; do
                sname=$(echo "$sline" | sed -n 's/.*name=\([^ ]*\).*/\1/p')
                saddr=$(echo "$sline" | sed -n 's/.*address=\([^ ]*\).*/\1/p')
                [ -z "$sname" ] && continue
                echo "        +-- $sname -> $saddr"
            done
        fi
    fi
done
