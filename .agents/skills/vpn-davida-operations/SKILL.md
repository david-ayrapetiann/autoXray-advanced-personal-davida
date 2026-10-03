---
name: vpn-davida-operations
description: Operate the VPN-Davida multi-server project safely. Use for user provisioning, central subscription changes, new-node deployment, server migration, WARP/Xray/HAPP diagnostics, and generated landing-page maintenance.
---

# VPN-Davida operations

Use this skill whenever a request touches the VPN-Davida infrastructure, its
subscription generator, user pages, Xray, WARP, HAPP, a new server, or a
migration. The project is production infrastructure: preserve access, make
small reversible changes, and do not expose secrets.

## First response and scope

1. **Mandatory Long-Term Memory Protocol (System Memory Graph):**
   - **BEFORE any action:** Read `/etc/vpn-davida/SYSTEM_MEMORY.md` on Switzerland (`198.51.100.11`), or local `references/current-state.md`, or via CLI `davida memory show`.
   - Treat `SYSTEM_MEMORY.md` as the single source of truth for node IPs, ports (SSH 23432, user `vpnadmin`), active security rules (Rules 1, 2, 3), and conventions.
   - **AFTER any change:** Record the change into `/etc/vpn-davida/CHANGELOG.md` using the CLI or direct append:
     ```bash
     davida memory log "Краткое описание изменений, затронутые файлы, точка отката"
     ```
2. Identify whether the request is read-only, a user/catalog change, a
   page-only change, a routing/WARP change, a new-node deployment, or a
   migration.
3. Read [the current state](references/current-state.md) and then only the
   procedure matching the request.
4. Treat all old local staging files and older handoffs as historical evidence,
   not as the current source of truth. Verify the live source before a write.
5. Never show credentials, bearer subscription URLs, UUIDs, Reality keys,
   passwords, complete Xray configs, or full generated subscriptions.

## Routing map

| Request | Read next |
|---|---|
| Current health, list of nodes, architecture | [current state](references/current-state.md) & `/etc/vpn-davida/SYSTEM_MEMORY.md` |
| History of changes, decision logs | `/etc/vpn-davida/CHANGELOG.md` & `davida changelog` |
| Add, remove, rename, or inspect a user | [users](references/users.md) & `davida user` |
| Supported script actions or CLI reference | [command reference](references/command-reference.md) & `davida help` |
| Deploy a clean VPS / join a node (1-Click) | [new server](references/new-server.md) & `installer/davida_node_setup.sh` |
| Move users, a node, or the subscription authority | [migration](references/migration.md) |
| Change landing pages, labels, or generated web files | [pages](references/pages.md) |
| Slow traffic, Xray, WARP, DNS, HAPP, Telegram, or client routing | [diagnostics](references/diagnostics.md) |
| Need historical rationale | [history](references/history.md) |
| Full handoff, topology, roster, or transfer to another agent | [project overview](references/project-overview.md) |

Read [safety rules](references/safety.md) before any write to a server.

## Non-negotiable operating rules

- **Switzerland (`198.51.100.11`) is the Central Master Authority** (Finland was decommissioned). Subscriptions, Web Portal, Admin Panel, and User DB reside on Switzerland.
- All cluster nodes use SSH port **`23432`** and administrative user **`vpnadmin`** with Ed25519 key authentication. Password login is disabled.
- **HAPP Routing Requirement:** The Nginx `/sub/` location MUST return `routing: happ://routing/onadd/<b64>` and `routing-enable: 1` headers with `Access-Control-Expose-Headers` exposing them, otherwise HAPP client split tunneling fails.
- Maintain the 3 Security Rules:
  1. Fail2ban jail `nginx-404` and `sshd` with `backend = systemd`.
  2. PIN Gate on personal user landing pages (`/nect/<user>`) with PBKDF2 hashed PINs in `/etc/vpn-davida/passwords.json`.
  3. Direct IP scanning protection: port 80 returns `444`, port 443 rejects TLS handshake (`ssl_reject_handshake on`).
- Before a write: make a dated backup, keep the existing SSH session open, make
  the smallest change, validate it, then test the user-facing result.
- After every write: record the modification in `CHANGELOG.md` via `davida memory log`.
- Use the unified 1-Click installer `davida_node_setup.sh` for onboarding new nodes.
- `sync` regenerates user subscriptions from the central catalog. Never hand
  edit generated user JSON as a persistent fix.
- Treat the current HAPP crash investigation as unresolved. Do not reintroduce
  fake profiles or optional HAPP metadata without explicit user approval and a
  rollback plan.

## Completion standard

Report the exact scope changed, the reversible backup point, evidence that
the replacement works, and confirmation that `CHANGELOG.md` was updated. State
separately what was not tested end-to-end (for example, a client app on the
user's phone).
