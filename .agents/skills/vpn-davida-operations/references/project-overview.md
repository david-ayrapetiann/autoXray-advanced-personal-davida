# VPN-Davida project handoff

This is the detailed, secret-free map of the production project. It is a
handoff aid, not a replacement for a fresh read-only audit. Live state wins
over every value in this document.

## Current production topology

| Role | Public address | Public name | SSH port | Status |
|---|---|---|---:|---|
| **Switzerland (Master)** | `198.51.100.11` | `vpn-ch.example.com` | 23432 | 🟢 Active Central Authority |
| **Estonia (Edge)** | `198.51.100.12` | `vpn-ee.example.com` | 23432 | 🟢 Active Edge Node |
| **Germany (Edge)** | `198.51.100.13` | `vpn-de.example.com` | 23432 | 🟢 Active Edge Node |
| Finland (Decommissioned) | `198.51.100.14` | `vpn.example.com` | N/A | ⚪ Decommissioned |

All active nodes run Xray VLESS + Reality TCP/443 profiles + AmneziaWG UDP/443.
SSH authentication uses user `vpnadmin` with Ed25519 key authentication. The key passphrase is never stored in this repository.

## Authority and generated artifacts

**Switzerland (`198.51.100.11`) is the central master authority.** The user registry, catalog, branding, generated subscription JSON, and personal web landing pages reside on Switzerland.

Primary live paths on Switzerland:

- `/root/autoXRAY_davida_custom.sh` — operations script, profile generator, web templating.
- `/usr/local/bin/autoXRAY_davida_custom` — installed wrapper.
- `/etc/vpn-davida/users.txt` & `/etc/vpn-davida/users.json` — user registries.
- `/etc/vpn-davida/passwords.json` — user PIN hashes (PBKDF2-HMAC-SHA256).
- `/etc/vpn-davida/servers.conf` — secret-bearing node catalog; mode 600.
- `/etc/vpn-davida/current.env` and `branding.conf` — runtime/branding configurations.
- `/etc/vpn-davida/SYSTEM_MEMORY.md` & `CHANGELOG.md` — memory graph and operation logs.
- `/opt/vpn-davida-panel/davida_core.py` — Python backend daemon & REST API.
- `/var/www/vpn-ch.example.com/_core/subscription.json` — base subscription template.
- `/var/www/vpn-ch.example.com/sub/` — generated per-user JSON (legacy `<user>.json` + capability `<user>_<UUID>.json`).
- `/var/www/vpn-ch.example.com/nnect/` — generated per-user HTML landing pages (with PIN gate).
- `/var/www/vpn-ch.example.com/servers.json` — public catalog projection.
- `/usr/local/etc/xray/config.json` — server Xray configuration.

The generator owns generated JSON and HTML. A manual edit to `sub/` or `nnect/`
is not durable and will be overwritten by `sync` or `webfix`.

## Users and naming

The live snapshot contained a set of technical IDs and matching generated
subscriptions. The roster is deliberately not reproduced here; query the live
registry privately when a count or an identifier is needed.

This is a dated snapshot, not permission to expose a registry. Before adding
or renaming anyone, query the live registry privately. Technical IDs must
match `^[A-Za-z0-9_-]{2,32}$`; decorative names belong in the generator's
display/title map. Known examples include ExampleUser's heart in the page title and
ExampleUser2's decorative display name. Do not encode decoration into transport IDs.

## Transport and client policy

The server path is Xray VLESS Reality RAW/TCP on 443 with Nginx fallback.
Validate the server configuration with `xray run -test`; a running service is
not by itself proof that a phone or desktop client can connect.

Generated client routing is separate from server Xray routing:

- Russian direct rules remain client-side, including the `geoip:ru` policy.
- Telegram domains are intended to use the proxy rule, not a direct rule.
- Rule order matters: the first matching rule wins.
- Do not move these policies into server Xray or remove them without an
  explicit routing change request and a rollback plan.

## WARP policy

All named nodes use the same intended mechanism: official Cloudflare WARP CLI
in local proxy mode on `127.0.0.1:40000`. WARP is only for Google AI traffic
(Gemini, AI Studio, Flow and related AI endpoints). Google Search, YouTube,
and ordinary Google services remain outside the WARP rule. WireProxy,
Warproxy, and wireproxy experiments are historical and must not be silently
reintroduced. Verify service, listener, exclusions, and a bounded request
before claiming a performance fix.

## Landing pages

The active page is the `HTML_TEMPLATE` heredoc in the live generator. The
current design has a central animated aurora, grain, black bottom falloff,
ultra-wide side dimming with a faint reflection, fixed-width action controls,
centered identity, brighter `Personal VPN`, and a soft username glow. There is
no separate mobile layout breakpoint now; the same grid composition is used
across widths and the name is fitted only when it cannot physically fit.

The primary actions must remain download HAPP, open/add the subscription, copy
the subscription URL, donation choices, and Telegram/MAX contact links. The
page may be visually rich, but it must not add HAPP `support`, `blackhole`,
`serverDescription`, fake profiles, or unknown subscription fields.

## HAPP compatibility baseline

The safe subscription contains exactly four real profiles and no custom
subscription metadata/header experiments. HAPP 4.2.1.608 previously imported
the real profiles but was also reported to crash; the root cause remains
unproven. If a crash returns, preserve the current artifact, validate JSON and
individual profiles, and test a minimal rollback before changing DNS/routing.

## Release and rollback runbook

1. Read the live script dispatch and identify the actual target domain(s).
2. Back up the live generator and any source catalog file with a dated name.
3. Stage the smallest change; never reinstall a working node for a page or
   label update.
4. Run `bash -n` and, for Xray/Nginx changes, their respective config tests.
5. Use `webfix <domain>` for page/template changes; use `sync <domain>` after
   a user or central-profile catalog change. `serverfix`/`catalog` updates the
   separate Amnezia server-list projection and is not a substitute for editing
   VLESS profile remarks.
6. Verify HTTP/page output, profile order/labels structurally, services, and
   a real client when available.
7. If a regression appears, restore the named backup, rerun the same narrow
   generator action, and recheck the public page.

## Known limitations

- Current counts, IPs, fingerprints, labels, and service state can change;
  refresh them before a new operation.
- Passwords, private keys, bearer links, UUIDs, Reality credentials, complete
  configs, and raw subscription JSON intentionally do not belong in this
  package.
- A public HTTP 200 proves delivery only; it does not prove HAPP behavior,
  client DNS, DPI traversal, WARP exclusion correctness, or throughput.
