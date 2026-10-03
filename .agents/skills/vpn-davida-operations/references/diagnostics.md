# Connectivity, WARP, Xray, HAPP, and performance diagnostics

## Diagnose in layers

Do not make broad changes before locating the layer:

1. VPS: service state, listener, firewall, TLS/Nginx fallback, CPU/memory,
   packet loss, routing, BBR/sysctl.
2. Profile: generated JSON parses, expected count and order, Xray accepts each
   individual profile.
3. Subscription delivery: public endpoint status and client import/refresh.
4. Client: HAPP version/logs/cache/routing files, app crash evidence, local DNS
   and network behavior.
5. External path: DPI/provider/client-network effects. Server reachability is
   not proof of this layer.

## WARP standard

Use only the official Cloudflare WARP CLI mechanism on every node. The intended
local proxy listener is `127.0.0.1:40000`. Verify service state, local listener,
and behavior with controlled domain tests. WARP scope is Google AI only
(Gemini, AI Studio, Flow); Google Search and YouTube must remain excluded.

Do not call performance “fixed” from a process status alone. Measure baseline,
run a bounded test through the intended route, and compare latency/throughput
from the same test location. Avoid changing WARP backend, MTU, BBR, DNS, and
routing all at once: it makes regression diagnosis impossible.

## Client routing

The direct/proxy decisions seen by a user are usually in the generated client
subscription routing rules, not in the server's core Xray inbound. Rule order
matters: first match wins. Historical work routed Telegram domains via proxy and
kept Russian direct rules. Do not edit this because of a report alone; back up,
inspect the exact generated source, and confirm the desired policy.

## HAPP crash guardrail

The current safest published artifact has four real profiles and no custom
`support` / `serverDescription` metadata. Earlier fake information profiles and
custom headers were removed after crashes were reported. The cause is still not
confirmed. If HAPP crashes again:

- record app version, crash timestamp, import/refresh action, and whether a
  clean/simplified subscription changes it;
- validate the subscription JSON without printing contents;
- test profiles individually with Xray's config test where safe;
- preserve client routing/DNS evidence before changing it;
- propose a limited rollback or a simplified test artifact, and obtain explicit
  approval before removing client routing/DNS policy.

## DNS and MTU

DNS or MTU tuning can help only when evidence points there. Check resolution
latency/failures, path MTU/fragmentation symptoms, and client network type first.
Treat server BBR, client MTU, and client DNS as distinct. Record baseline and
one-variable-at-a-time results; retain a rollback value.
