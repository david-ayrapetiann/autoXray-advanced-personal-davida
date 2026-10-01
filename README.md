# 🛡️ Distributed Multi-Node Anti-Censorship VPN Cluster

A production-grade, distributed VPN cluster designed for high reliability, automated client onboarding, and robust censorship circumvention. 

Built on top of **Xray-core Reality (VLESS over TCP 443 with Vision / TLS camouflaging)** and **AmneziaWG**, with an automated dynamic node catalog, SQLite telemetry metrics collector, PIN-protected client portals, and unified routing configurations.

---

## 🌟 Key Architecture & Features

```
                               ┌────────────────────────────────────────┐
                               │       Central Authority Node           │
                               │  - Nginx Reverse Proxy (SNI hardening) │
                               │  - Davida Panel API (Python / SQLite)  │
                               │  - User Subscriptions & Landing Pages  │
                               └──────────────────┬─────────────────────┘
                                                  │ Cluster SSH & Stats
                  ┌───────────────────────────────┼───────────────────────────────┐
                  ▼                               ▼                               ▼
       ┌─────────────────────┐         ┌─────────────────────┐         ┌─────────────────────┐
       │   Edge Node (CH)    │         │   Edge Node (EE)    │         │   Edge Node (DE)    │
       │ Xray Reality :443   │         │ Xray Reality :443   │         │ Xray Reality :443   │
       │ AmneziaWG   :443    │         │ AmneziaWG   :443    │         │ AmneziaWG   :443    │
       └─────────────────────┘         └─────────────────────┘         └─────────────────────┘
```

1. **Protocol Camouflage (XTLS Reality)**
   - VLESS with `xtls-rprx-vision` over TCP port 443.
   - Steals TLS handshake signatures from genuine third-party websites without needing domain certs on edge nodes.
   - Resilient against Active Probing, Deep Packet Inspection (DPI), and SNI blocklists.

2. **Split Routing (Censorship Circumvention)**
   - Custom routing rules for HAPP / Hiddify:
     - Direct routing for domestic/Russian banking, state portals, and local services (`geosite:category-ru`, `geoip:ru`).
     - Proxy routing for international and blocked traffic.
     - Built-in DNS leak protection via DNS-over-HTTPS (DoH).

3. **Dynamic Node Catalog (`cluster-node.sh`)**
   - Single source of truth (`/etc/vpn-cluster/nodes.json`).
   - Add or decommission cluster nodes in seconds without touching core code or restarting active tunnels.
   - Automatically synchronizes node lists to all client subscription endpoints.

4. **Lightweight Python Observability Panel**
   - Background polling daemon collecting live round-trip latency, CPU load, and socket connection states across all cluster nodes.
   - SQLite time-series storage.
   - Secret rotation mechanism across the entire fleet via inter-node SSH.

5. **Personalized Client Web Portals**
   - High-craft mobile-responsive web pages (`/nnect/<username>.html`).
   - One-click "Add to HAPP" deep links, Amnezia config downloads, and step-by-step onboarding.
   - Secured with optional PIN authentication and rate-limiting.

---

## 📁 Repository Structure

```
.
├── config/
│   └── nodes.example.json      # Dynamic cluster node definitions
├── nginx/
│   └── nginx-vpn.conf          # Nginx reverse proxy configuration with SNI protection
├── panel/
│   ├── panel_core.py           # Core Python backend daemon & REST API
│   └── requirements.txt        # Python dependencies
├── scripts/
│   ├── autoxray.sh             # Main orchestration & profile generator script
│   └── cluster-node.sh         # Dynamic node management CLI
└── systemd/
    └── vpn-panel.service       # Systemd service unit for the panel
```

---

## 🚀 Quick Start Guide

### 1. Prerequisites
- Central server: Debian 12 / Ubuntu 22.04+ with public IPv4.
- Registered domain name pointing to the central server.
- Edge nodes: Clean Linux servers with SSH key access from the central node.

### 2. Node Configuration
Copy `config/nodes.example.json` to `/etc/vpn-cluster/nodes.json` and configure your cluster nodes:
```json
[
  {
    "id": "ch",
    "name": "🇨🇭 Switzerland",
    "dc": "Infomaniak",
    "ip": "198.51.100.10",
    "port": 443,
    "amnezia_url": ""
  },
  {
    "id": "de",
    "name": "🇩🇪 Germany",
    "dc": "Dataforest",
    "ip": "198.51.100.30",
    "port": 443,
    "amnezia_url": ""
  }
]
```

### 3. Dynamic Node Management
Use the `cluster-node.sh` utility to manage your cluster:

```bash
# Add or update a node
sudo ./scripts/cluster-node.sh add de "🇩🇪 Germany" "Dataforest" 198.51.100.30 ""

# Remove a node
sudo ./scripts/cluster-node.sh rm de

# List all active nodes
sudo ./scripts/cluster-node.sh list
```

### 4. Client Subscriptions
Generate client profiles:
```bash
# Add a new client
sudo ./scripts/autoxray.sh adduser vpn.example.com alice

# Re-sync all client profiles after node changes
sudo ./scripts/autoxray.sh sync vpn.example.com
```

Clients receive:
- Universal subscription URL: `https://vpn.example.com/sub/alice.json` (consumable by HAPP, Hiddify, v2rayN, Sing-Box).
- Personal landing page: `https://vpn.example.com/nnect/alice.html`.

---

## 🔒 Security & Privacy Notice

- **No Logging**: Outbounds are configured with `loglevel: warning` to avoid recording user browsing habits.
- **Fail-Safe Fallbacks**: Nginx drops direct IP scans (`return 444`) and rejects unrecognized SNI handshakes (`ssl_reject_handshake on`).
- **Encrypted Inter-Node Communications**: All fleet management runs through ED25519-authenticated SSH channels on custom ports.

---

## 📄 License
MIT License. Created for secure, uncensored internet access.
