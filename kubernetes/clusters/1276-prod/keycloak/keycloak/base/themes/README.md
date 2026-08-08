# TechGarden Keycloak theme (`techgarden`) — prod copy

The 17 files under `techgarden/` are **byte-identical to the dev copy** at
`kubernetes/clusters/1276-dev/keycloak/keycloak/base/themes/techgarden/`.

**The dev copy's README is the canonical documentation** — how the theme is built,
which surfaces it themes, how to iterate on it locally against a real 26.6.3
container, the MessageFormat quoting trap, the shared-message-key trap, and the OFL
font licence obligation. It is deliberately **not duplicated here**: that README
itself warns that a stale second copy nobody deletes is the failure mode WS-05 was
shaped to avoid. Read it there; change the theme in both places in one PR.

## What is different in prod

**Nothing in the theme files.** Only two things about how they are wired:

1. **`techgarden.gg/theme-revision` starts at `1` and counts independently.**
   Dev is on `2` (it absorbed the WS-05 stage-3 `emailSentMessage` fix). The two
   clusters' revision numbers do not relate and must never be "synced up" — each
   one only has to *change* to force its own pod roll. Bump prod's on every change
   under `base/themes/`.

2. **The realm that would use this theme is not loaded yet.**
   `base/realms/techgarden-realm.json` exists but is deliberately absent from
   `configMapGenerator.files` in `../../kustomization.yaml`. Until that one line is
   added at the flip, `https://sso.techgarden.gg/realms/techgarden` returns 404 and
   this theme is mounted but unreferenced. That is the intended state.

## Why the mount is two ConfigMaps, not one

`configMapGenerator` keys off each file's **base name**, and ConfigMap keys cannot
contain `/`. `theme.properties` and `messages_en.properties` each exist under **both**
`login/` and `email/`, so a single ConfigMap collides on those two keys. One ConfigMap
per theme type removes the collision without renaming anything; the volume's
`items[].path` then rebuilds the subdirectory layout that the generator flattened away.
