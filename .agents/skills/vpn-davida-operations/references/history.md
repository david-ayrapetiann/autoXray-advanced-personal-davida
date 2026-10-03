# Project history and decisions

This is a concise operating history. It explains why the current constraints
exist; it is not a substitute for fresh inspection.

## Timeline

- The project began as a custom multi-server Xray/VLESS Reality deployment with
  a central subscription generator and personal web pages.
- Finland became the central authority for users, server catalog, subscription
  JSON, and generated pages. Estonia initially carried some user-specific
  material, which was later migrated into the Finnish central workflow.
- Estonia, Germany, and then Switzerland were added as subscription profile
  nodes. The currently intended subscriber order is Switzerland, Finland,
  Estonia, Germany, with the labels тест, норм, норм, and запас.
- On 2026-09-15 the central profile remarks were corrected from `премиум` to
  `тест` for Switzerland and from `плохой` to `запас` for Germany. The central
  catalog was backed up before the change, then all 27 user subscriptions were
  regenerated and structurally checked.
- Several WARP approaches were explored. The deliberate end state is a uniform
  official WARP CLI local-proxy pattern on all nodes, restricted to Google AI
  services and excluding Google Search/YouTube.
- Client-side Russian-direct and Telegram-proxy routing were maintained in the
  generated subscription logic. This is client policy, not proof that server
  Xray itself is misconfigured.
- The personal pages went through several visual directions. Page styling must
  now be changed in the live generator/template, not by editing rendered output
  or reinstalling infrastructure.
- A fake subscription item intended to show donations/support, plus additional
  custom HAPP metadata/header experiments, was introduced and then removed
  after HAPP crashes were reported. The current production baseline contains
  only the four real profiles and avoids those extensions.

## Durable lessons

- The source script is the durable control plane; generated artifacts are not.
- New-node deployment, catalog changes, user provisioning, routing changes,
  and visual releases have different blast radii and should not be combined.
- Keep a backup and a working SSH session during every production change.
- A server-side green status is useful but does not prove that a user client,
  mobile network, or a DPI-affected path works.

## Superseded local documents

Older handoffs, older page templates, and stage scripts remain valuable as
historical references. They may carry outdated user counts, hashes, labels, or
configuration logic. Compare them with the live Finland source before reuse.
