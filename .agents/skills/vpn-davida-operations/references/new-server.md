# Deploy a clean server and join it to the project

This is a staged production change. Do not turn a clean VPS into a catalog node
until its base connection works and it has a defined rollback path.

## Phase 0 — authorization and inventory

Collect from the user: hostname/domain, current address, authorized access
method, intended country/label/rank, and whether it should be part of all user
subscriptions. Never place supplied credentials into this skill, command
history, or final answer.

Perform a read-only baseline:

- OS/version, disk and memory, provider network, current listeners;
- firewall, SSH configuration, Xray/Nginx/Docker/WARP presence;
- current SSH host key and access route;
- DNS resolution and the intended public name.

## Phase 1 — access and hardening

Keep root/current access alive while creating and testing a dedicated
administrative account with key-based login. Only after a separate SSH session
works should root/password restrictions or the SSH port be changed. Use a
minimal firewall: SSH management port, TCP/443 for VLESS/Reality, and only the
explicitly authorized UDP service ports. Validate firewall persistence and
reconnect from a second session before ending the first.

## Phase 2 — deploy the standard node (1-Click Installer)

Use the unified 1-Click deployment script `davida_node_setup.sh`:

```bash
curl -sSL https://vpn.example.com/installer/davida_node_setup.sh | bash -s -- setup \
  --name "<Country Name>" \
  --dc "<Datacenter Name>" \
  --secret "<retrieve the current join secret through an approved secure channel>"
```

The script automatically executes:
1. Base dependencies, packages, and TCP BBR congestion control.
2. User `vpnadmin` creation, sudoers `NOPASSWD`, and Ed25519 public key installation.
3. SSH hardening on port `23432` with password auth disabled.
4. UFW firewall lockdown: only `23432/tcp`, `443/tcp`, `443/udp`, and `80/tcp` allowed.
5. Fail2ban configuration with `backend = systemd`.
6. Cloudflare WARP SOCKS5 client on `127.0.0.1:40000`.
7. Xray-core Reality installation with Google AI WARP routing.
8. Registration with Central Authority (Finland) via `/api/nodes/join`.

Run audit mode to verify compliance:
```bash
bash davida_node_setup.sh check
```

## Phase 3 — WARP and performance

First measure the ordinary baseline. Then configure the uniform official WARP
CLI design only if the base VLESS path is healthy. Confirm local WARP service
state and SOCKS listener, then test that only designated Google AI traffic uses
it while Search and YouTube remain outside it. Keep a rollback copy of routing
rules and do not mix WireProxy/Warproxy with WARP CLI.

## Phase 4 — publish to the central catalog

On Finland, back up `servers.conf` and the generator, add the new node using
the script-supported catalog flow, then run `sync`. Verify each generated
subscription structurally has the expected profile count and intended ordering.
Confirm a new server is visible to one test user before treating it as deployed
for all users.

## Completion checklist

Record only redacted facts: node role/label, services healthy, catalog refresh
finished, profile count, and rollback backup paths. Never paste connection
strings, tokens, or passwords.
