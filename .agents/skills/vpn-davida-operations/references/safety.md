# Safety rules and secret handling

## Do not disclose

Never print, commit, upload, or include in a handoff:

- root or non-root passwords, SSH private keys, host-authentication material;
- UUIDs, Reality private/public credentials, bearer URLs, or complete profile
  strings;
- the contents of `current.env`, `branding.conf`, complete Xray config files,
  raw generated subscriptions, or Nginx logs containing tokens.

When evidence is necessary, report structure and status only: file exists,
JSON validates, profile count, service health, or a redacted identifier.

## Before any server write

1. Make a dated backup of every target configuration and record its path.
2. Keep the current working SSH session open.
3. If SSH policy is changing, first prove a separate new-key/new-user session.
   Only then disable root or password login.
4. Check syntax before restart: shell syntax for scripts, JSON validation for
   JSON, `nginx -t` for Nginx, and Xray's config test where appropriate.
5. Restart only the service that needs restarting and immediately confirm it is
   active and listening as expected.
6. Test the public/consumer surface without revealing a bearer URL: HTTP status,
   page rendering, subscription JSON structure, and one client import when the
   user can test it.

## The established script is authoritative

The required workflow is the live `autoXRAY_davida_custom.sh` with its
documented commands. It owns the catalog and generated files. A local copy
must be compared with the live copy before it replaces anything.

- `sync` regenerates the server catalog, client Russian-routing rules, and all
  user subscription artifacts.
- `webfix` regenerates/repairs the web-facing artifacts. Identify exactly which
  domains it touches before running it.
- `serverfix` / `catalog` is for server catalog work; it is not a user-page
  refresh.
- `install` is invasive. Use it only for a user-authorized clean-node install,
  never for routine maintenance.

## Do not make these shortcuts

- Do not patch a generated `sub/<user>.json` or `nnect/<user>.html` and call it
  a durable fix; the next `sync` can overwrite it.
- Do not reuse historic credentials or assume a node's current IP, host key,
  service layout, or WARP registration.
- Do not claim a server-side check proves a phone/desktop client works through
  its network. Those are separate tests.
- Deleting a user does not revoke profiles they already copied. For revocation,
  plan credential rotation/re-provisioning.
- Do not use unsafe multi-line PowerShell/SSH one-liners. Prefer short,
  independent read-only checks or a temporary UTF-8 LF script transferred and
  executed deliberately.
