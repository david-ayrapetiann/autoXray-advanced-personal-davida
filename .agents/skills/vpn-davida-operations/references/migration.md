# Migrations and catalog changes

## Principles

The Finland authority is the central catalog unless the user explicitly asks to
migrate authority itself. A node migration and an authority migration are
different projects. Make an inventory and cutover plan first; do not start by
deleting the old server.

## Add/replace a profile node

1. Bring up the replacement as a clean node according to
   [new-server.md](new-server.md).
2. Build and test its profile outside the production catalog.
3. Back up Finland's `servers.conf`, generator, and generated catalog.
4. Add it as a separate profile; keep the old profile present for a transition
   if the user has not explicitly asked for an immediate removal.
5. Run the supported catalog refresh (`sync`) and verify one redacted
   subscription structure and public page.
6. Test from a real client, then reorder/remove the old profile only after the
   new one is proven.

## Move the central authority

This is higher risk. Draft and get approval for a migration plan covering:

- exact source and destination domains plus DNS/TLS cutover;
- all secret-bearing state (`current.env`, branding/bearer data, server
  catalog, users, generator logic, Xray/Nginx state) transferred securely;
- database/filesystem preservation and ownership/mode checks;
- a read-only/preview validation on the destination;
- rollback DNS and source-server retention period;
- client behavior during existing subscription auto-updates.

Do not expose the contents of those files in chat. Prefer an encrypted or
direct server-to-server transfer and validate hashes/permissions privately.

## User migration boundaries

“Only Estonia” or similar wording is not shorthand for a global catalog update.
Keep it an explicit exception. The normal `sync` path can overwrite manual
per-node user artifacts, so encode the exception in the supported source logic
or do not perform it until an enduring design is agreed.

## Completion evidence

At minimum, prove source preserved, destination services healthy, central
catalog intact, profile ordering correct, generated JSON parses, and a real
client can connect. Report the date and rollback condition for retiring source
infrastructure.
