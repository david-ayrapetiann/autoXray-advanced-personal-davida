## Unified `davida` CLI reference

The primary administrative command line utility is `/usr/local/bin/davida`:

| Command | Purpose |
|---|---|
| `davida memory [show]` | Displays the central long-term memory (`SYSTEM_MEMORY.md`). |
| `davida memory log "<msg>"` | Appends a structured record to `CHANGELOG.md` with UTC timestamp and caller info. |
| `davida changelog` | Displays `CHANGELOG.md`. |
| `davida users` | Lists all users, assigned PINs, and personal landing URLs. |
| `davida user add <user> [pin]` | Adds a user, generates PIN, generates subscription and personal page. |
| `davida user pin <user> <pin>` | Updates a user's PIN in `passwords.json` and updates their landing page. |
| `davida user del <user>` | Removes a user and associated artifacts. |
| `davida status` | Audits local services and TCP ping latency to all cluster nodes. |
| `davida sync` | Runs cluster subscription and web synchronization. |

## Legacy script actions (`autoXRAY_davida_custom.sh`)

The underlying generator implementation is `/root/autoXRAY_davida_custom.sh`:

| Action | Intended effect | Guardrails |
|---|---|---|
| `adduser <domain> <technical-id>` | Registers one user and generates the user's artifacts | Validate ID first; do not disclose the resulting connection link. |
| `sync <domain>` | Rebuilds the server catalog projection, client Russian-routing rules, and all user subscription artifacts | Back up source inputs first; expect it to overwrite generated JSON/pages. |
| `webfix` | Repairs/regenerates web-facing artifacts | Identify target domains and paths first; it is not a substitute for a catalog migration. |
| `serverfix <domain>` / `catalog <domain>` | Updates the separate Amnezia server-list projection | It is not the VLESS profile-label source; verify only when that projection is in scope. |
| `install` | Performs an invasive base deployment | Allowed only for an explicitly approved clean new-node deployment. |

## Safe routine sequence

1. Read the live script's help/dispatch and confirm the action still exists.
2. Back up the source inputs affected by that action.
3. Run one supported command, not a chain of unrelated commands.
4. Inspect service state and redacted artifact structure.
5. If the action was `sync`, confirm both a representative web page and a
   representative subscription JSON were regenerated successfully. For a
   profile-label change, check every generated user file has the same four
   remarks and order.

## Pre-flight checks

Use brief independent checks rather than a fragile large remote command:

- script hash/date and relevant function/dispatch names;
- ownership and mode of configuration directories;
- JSON and shell syntax;
- `systemctl is-active` for Xray/Nginx/WARP as relevant;
- `nginx -t` before Nginx reload;
- an Xray config/profile test where suitable.

Do not copy the live script back from an unverified local checkout. The local
file may be a staging snapshot, while the live script is what generates the
active production artifacts.
