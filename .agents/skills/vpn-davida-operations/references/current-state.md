# Current project state

Last live-source refresh: 2026-10-02. This document records operational state,
not credentials. Re-check live status before taking action because VPS and
client state can change.

## Architecture

**Switzerland (CH, `198.51.100.11`) is the primary Central Authority** for the VPN-Davida subscription catalog, web portal, API daemon, and database. Finland was decommissioned. The active cluster consists of 3 nodes:

1. **Switzerland (CH, `198.51.100.11`)** — Central Authority / Master (Infomaniak Tier III+, Geneva)
2. **Estonia (EE, `198.51.100.12`)** — Edge Node (Infonet / AstraVPS, Tallinn)
3. **Germany (DE, `198.51.100.13`)** — Edge Node (Dataforest / DE-CIX, Frankfurt)

All nodes run Xray Reality RAW/TCP on port 443 with Nginx HTTPS fallback, plus AmneziaWG on UDP port 443.

## Central live source of truth

On the **Switzerland** authority, inspect these paths:

| Purpose | Live location |
|---|---|
| Central System Memory Graph | `/etc/vpn-davida/SYSTEM_MEMORY.md` |
| Changelog & Decision Log | `/etc/vpn-davida/CHANGELOG.md` |
| Unified Management CLI | `/usr/local/bin/davida` & `/root/autoXRAY_davida_custom.sh` |
| Installed command wrapper | `/usr/local/bin/autoXRAY_davida_custom` |
| Davida Core Web Panel & API | `http://127.0.0.1:8888/` (`https://vpn-ch.example.com/admin/`) |
| User PIN/Password database | `/etc/vpn-davida/passwords.json` (PBKDF2-HMAC-SHA256) |
| User registry | `/etc/vpn-davida/users.txt` & `/etc/vpn-davida/users.json` |
| Server catalog | `/etc/vpn-davida/servers.conf` |
| Runtime state / secrets | `/etc/vpn-davida/current.env` |
| Branding / bearer settings | `/etc/vpn-davida/branding.conf` |
| Generated subscription core | `/var/www/vpn-ch.example.com/_core/subscription.json` |
| Generated user JSON (Legacy) | `/var/www/vpn-ch.example.com/sub/<user>.json` |
| Generated user JSON (Capability) | `/var/www/vpn-ch.example.com/sub/<user>_<UUID>.json` |
| Generated personal pages | `/var/www/vpn-ch.example.com/nnect/` (alias `/nect/`) |
| Published server list | `/var/www/vpn-ch.example.com/servers.json` |
| HAPP guide | `/var/www/vpn-ch.example.com/guide/happ.html` |
| Xray configuration | `/usr/local/etc/xray/config.json` |
| Telemetry SQLite DB | `/opt/vpn-davida-panel/metrics.db` |

[REDACTED — compare against the live script at deployment time.]
This is a comparison aid, not a promise that it remains current.

## Observed live health snapshot

On 2026-09-15 Finland had 27 registered users, four core profiles, and 27
generated user subscriptions. Xray and Nginx were active. The central
subscription's relevant top-level optional fields were `dns`, `meta`, and
`routing`; it did not include `support` or `serverDescription`.

The label update verified on 2026-09-15 changed only two ordinary profile
remarks: Switzerland is `тест` and Germany is `запас`; Finland and Estonia
remain `норм`. The rollback copy is
`/var/www/vpn.example.com/_core/subscription.json.before-label-update-20260915`;
all 27 generated user files were re-synced and checked for four profiles.

This count is only a snapshot. Use the project script's list command or a
read-only inspection of `users.txt` when a live count is needed; do not print
the registry in a broad log or chat.

## WARP design

Each node is intended to use the official Cloudflare WARP CLI as a local SOCKS
proxy on `127.0.0.1:40000`. Its scope is deliberately narrow: Google AI
services such as Gemini, AI Studio, and Flow should use WARP; Google Search,
YouTube, and ordinary Google services should not be forced through it. Keep one
mechanism on all nodes; do not silently mix WARP CLI and third-party proxies.

## HAPP compatibility & split-tunnel routing status

HAPP client split-tunnel routing requires specific Nginx response headers on `/sub/`:
- `routing: happ://routing/onadd/<b64>`
- `routing-enable: 1`
- `access-control-expose-headers: profile-title,profile-update-interval,routing,routing-enable`

The embedded rules route Russian domains (`geosite:category-ru`, `regexp:\.ru$`, `regexp:\.рф$`, banking, state services, search engines, marketplaces) and Russian IPs (`geoip:ru`, `geoip:private`) directly (`direct`), Telegram domains through proxy (`proxy`), and block ads/telemetry (`block`). If these headers are missing, client split tunneling fails.

## Local Git repository

- **Repository Path:** `C:\Users\admin\vpn-cluster`
- **Remote Origin:** `https://github.com/david-ayrapetiann/autoXray-advanced-personal-davida.git` (branch `main`)
- Contains sanitized orchestration bash scripts (`scripts/autoxray.sh`), node scripts, Python management daemon (`panel/panel_core.py`), and Nginx configs (`nginx/nginx-vpn.conf`).
