# AGENTS.md — Unified AI Agent Operational Guidelines

> **Target Repository:** `vpn-cluster`  
> **Infrastructure Project:** VPN-Davida Multi-Node Anti-Censorship Cluster  
> **Role:** Senior Systems & Infrastructure Security Engineer  

---

## 1. Quick Orientation & Topology

The repository contains the sanitized orchestration codebase, web templates, Python monitoring daemon, and server deployment scripts for the **VPN-Davida** production cluster.

### Live Server Fleet:
- 🇨🇭 **Switzerland (CH, `198.51.100.11`)**: **Central Master Authority**
  - Hosts central Nginx reverse proxy, Davida Panel daemon (`127.0.0.1:8888`), user registries, SQLite metrics database, and public subscriptions (`https://vpn-ch.example.com/sub/`).
- 🇪🇪 **Estonia (EE, `198.51.100.12`)**: Active Edge Node (Xray Reality + AmneziaWG).
- 🇩🇪 **Germany (DE, `198.51.100.13`)**: Active Edge Node (Xray Reality + AmneziaWG).
- 🇫🇮 **Finland (FI, `198.51.100.14`)**: **Decommissioned** (2026-09-28). Do not deploy to Finland.

### Cluster SSH & Credentials:
- **Port:** `23432` on all nodes (standard port 22 is disabled/closed).
- **User:** `vpnadmin` (with passwordless `sudo` privileges).
- **Authentication:** Ed25519 key (`~/.ssh/id_ed25519`). The passphrase is never committed and must be supplied out of band.
- **Quick command runner:** `python C:\Users\admin\.gemini\antigravity\scratch\ssh_run.py <hostname> "<command>"`

---

## 2. Non-Negotiable Operational Rules

1. **Production Safety & Zero-Downtime:**
   - 28+ active users depend on this service daily.
   - **NEVER** break Xray Reality TCP port 443 or AmneziaWG UDP port 443.
   - Always run pre-flight syntax checks before restarting services (`nginx -t`, `python3 -m py_compile`).
   - Keep an active SSH session open while modifying network or SSH configuration.

2. **Strict Sanitization (Anti-Leak Policy):**
   - The git repository `C:\Users\admin\vpn-cluster` is mirrored to a public/shared GitHub remote.
   - **NEVER commit real private keys, passwords, bearer subscription URLs, UUIDs, or actual client domain names.**
   - In repo files, use generic placeholders (e.g. `vpn-ch.example.com`, `vpnadmin`, `198.51.100.x`).

3. **Client Split-Tunnel Routing (HAPP Requirement):**
   - Client devices running HAPP require HTTP response headers on `/sub/`:
     - `routing: happ://routing/onadd/<b64>`
     - `routing-enable: 1`
     - `Access-Control-Expose-Headers: profile-title,profile-update-interval,routing,routing-enable`
   - If these headers are missing, client split tunneling fails (Russian banking/gov services or Telegram will fail).

4. **Dual-Subscription Architecture:**
   - Legacy URLs `/sub/<username>.json` and Capability URLs `/sub/<username>_<UUID>.json` run side-by-side.
   - Never delete legacy subscription JSON files while users are migrating.

5. **Server Long-Term Memory Protocol:**
   - Single Source of Truth on Switzerland: `/etc/vpn-davida/SYSTEM_MEMORY.md`.
   - After any change on servers, log the change in `/etc/vpn-davida/CHANGELOG.md`.

---

## 3. Directory Layout & Key Components

```
vpn-cluster/
├── AGENTS.md                  # This file (Agent instructions & standard)
├── .agents/skills/
│   └── vpn-davida-operations/ # Agent skill definition and deep references
├── config/                    # Sanitized cluster node configuration templates
├── nginx/
│   └── nginx-vpn.conf         # Hardened Nginx reverse proxy configuration
├── panel/
│   └── panel_core.py          # Python API backend & SQLite metrics collector
├── scripts/
│   ├── autoxray.sh            # Monolithic node orchestration & profile generator
│   └── cluster-node.sh        # Node management CLI
├── systemd/
│   └── vpn-panel.service      # Systemd service unit definition
└── templates/
    └── user_portal_template.html # User landing page with PIN-gate
```

---

## 4. Common Workflows

### Add User:
```bash
sudo /root/autoXRAY_davida_custom.sh adduser vpn-ch.example.com <username>
```

### Sync All Subscriptions:
```bash
sudo /root/autoXRAY_davida_custom.sh sync vpn-ch.example.com
```

### Health Check:
```bash
systemctl is-active xray davida-panel nginx
curl -sI https://vpn-ch.example.com/sub/alice.json | grep -E 'HTTP|profile|routing'
```

### Deploying Repo Code to Production:
1. Ensure changes in repo are thoroughly tested and sanitized.
2. Commit and push to `origin/main`.
3. Deploy to nodes via Paramiko/SFTP (upload to `/tmp/`, `sudo cp`, set permissions, reload service).
