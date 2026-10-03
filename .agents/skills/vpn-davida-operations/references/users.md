# User operations

## Add one user

Use the Switzerland Master authority (`vpn-ch.example.com`) unless the user explicitly limits the request to
another node. The technical identifier must match `^[A-Za-z0-9_-]{2,32}$`.
Keep a separate display-name mapping if the desired visible name contains
spaces, Cyrillic, emoji, or decorative characters.

1. Read the live user registry (`/etc/vpn-davida/users.txt`) and confirm that the technical identifier is not
   already present. Do not paste the whole registry into chat.
2. Back up the central registry, catalog, and generator source before changing
   them.
3. Invoke the live script's supported command:

   ```bash
   sudo /root/autoXRAY_davida_custom.sh adduser vpn-ch.example.com <technical-id>
   ```

4. If a display name or a special personal page title is requested, change the
   live generator/source mapping rather than the generated page or JSON.
5. Run the smallest required generator refresh (normally the supported script
   operation, not a full reinstall).
6. Verify, without exposing the link or JSON contents:
   - the expected page returns HTTP 200;
   - the matching JSON exists and parses;
   - it contains exactly the expected real profiles (currently four);
   - Xray and Nginx remain active.

## Rename or decorate a user

The technical ID and a visible display name are distinct. A safe decorative
change belongs in the generator's display/title mapping. For example, a heart
for one person's title must not alter the technical identifier, all users, or
the server profile remarks.

Do not add decorative `support`, `serverDescription`, fake profiles, or unknown
JSON fields to make a HAPP list look nicer. Current HAPP stability is under
investigation.

## Remove and revoke

First determine whether the request is only to stop publishing the user or to
revoke already copied credentials. The supported delete flow removes them from
future generated artifacts but does not invalidate copies already downloaded.
For a true revocation, plan a credential rotation and reissue the affected
profiles. Explain the disruption before starting.

## User-scoped server availability

The central subscription normally gives every user the same four real profiles.
A request such as “only Estonia” is a strict scope boundary: do not silently
add the user to the Finland central catalog or other nodes. First establish
whether it is intended as an exception and how it should survive `sync`.
