# L1.0 Attic Network - Complete RouterOS Configuration
# Target: Mikrotik CRS326-24G-2S+ (factory defaults)
# Network: 10.0.0.0/24 flat bridge, 8 ports, DHCP + DNS
# Deploy: config_deploy_from_rsc or /import file-name=L1.0-attic-network.rsc
#
# Prerequisites:
#   - Switch at factory defaults (192.168.88.1, admin, blank password)
#   - Direct ethernet connection to management port

# --- Bridge ---
/interface bridge add name=bridge-attic vlan-filtering=no comment="Attic server isolated network - 8 port flat bridge"

# --- Bridge Ports ---
/interface bridge port add bridge=bridge-attic interface=ether1 comment="NUC NIC 1 (management)"
/interface bridge port add bridge=bridge-attic interface=ether2 comment="NUC NIC 2 (data)"
/interface bridge port add bridge=bridge-attic interface=ether3 comment="Port 3 (available)"
/interface bridge port add bridge=bridge-attic interface=ether4 comment="Port 4 (available)"
/interface bridge port add bridge=bridge-attic interface=ether5 comment="Port 5 (available)"
/interface bridge port add bridge=bridge-attic interface=ether6 comment="Port 6 (available)"
/interface bridge port add bridge=bridge-attic interface=ether7 comment="Port 7 (available)"
/interface bridge port add bridge=bridge-attic interface=ether8 comment="Port 8 (available)"

# --- IP Address ---
/ip address add address=10.0.0.1/24 interface=bridge-attic comment="Attic network gateway"

# --- DHCP ---
/ip pool add name=pool-attic ranges=10.0.0.100-10.0.0.200
/ip dhcp-server add name=dhcp-attic interface=bridge-attic address-pool=pool-attic disabled=no
/ip dhcp-server network add address=10.0.0.0/24 gateway=10.0.0.1 dns-server=10.0.0.1 domain=attic.local

# Static lease for NUC
# TODO: Replace XX:XX:XX:XX:XX:XX with actual NUC MAC address, then uncomment the line below
# /ip dhcp-server lease add address=10.0.0.10 mac-address=XX:XX:XX:XX:XX:XX server=dhcp-attic comment="nux static lease"

# --- DNS ---
/ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes
/ip dns static add name=nux.attic.local address=10.0.0.10 comment="Attic cache server"
/ip dns static add name=attic.local address=10.0.0.10 comment="Attic server alias"
