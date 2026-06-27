# Keycloak — Topology & Operations

**Live:** `keycloak` namespace · codecentric/keycloakx chart · `quay.io/keycloak/keycloak:26.2`
· 2 replicas (prod) / 1 (dev) · serves `sso.techgarden.gg` (prod), `sso.dev.techgarden.gg` (dev)
· external CNPG DB `keycloak-db`. The Bitnami deployment under `*/techgarden/keycloak/` is
**not running** and is being removed — this codecentric deployment is the only live one.

## Identity model — hub & spoke

`accounts` is the single user store. Every other realm federates **into** it via an
`accounts` OIDC identity provider; users never live in the product (spoke) realms.

```
                 accounts  (users + broker-<spoke> clients)   ← the hub
                /     |        \              \
   IdP "accounts"  IdP "accounts"  IdP "accounts"   (master: broker client exists,
   techgarden     hausparty       kian-coffee        IdP not wired → unused)
   bff,svc.profile  hausparty     api.blog,kian-coffee-web
```

- **accounts** (hub) — users (`kian`, `techgardencode`), cross-realm roles (`infra-admin`,
  `app-admin`), one confidential `broker-<spoke>` client per spoke. Hardened: 14-char
  password policy, TOTP required, brute-force protection.
- **spokes** (`techgarden`, `hausparty`, `kian-coffee`) — each has an `accounts` IdP
  (syncMode FORCE) + a hardcoded-role IdP mapper, plus its app clients. No local users.
- **master** — admin-console realm. A `broker-master` client exists in `accounts` but master
  has **no** `accounts` IdP, so `broker-master` is currently unused cruft; admin login uses
  the local bootstrap admin.

> **Realm = product/tenant boundary.** Homelab/internal apps share the hub's identity; each
> public product gets its own spoke realm (a spoke may host several app clients). New homelab
> app = a new client in an existing realm; new product = a new spoke realm.

## Custom clients (Keycloak system clients omitted)

| Realm | Client | Type | Notes |
|---|---|---|---|
| accounts | `broker-{techgarden,hausparty,kian-coffee,master}` | confidential | broker-in clients |
| techgarden | `bff`, `svc.profile` | std-flow / service-account | **decommissioning (Stage 1)** |
| hausparty | `hausparty` | confidential, std flow | NextAuth; redirect `hausparty.techgarden.gg/*` |
| kian-coffee | `kian-coffee-web` | public + PKCE | Angular SPA; redirect `kian.coffee/admin/blog` |
| kian-coffee | `api.blog` | confidential / bearer | resource server; tokens carry `aud=api.blog` |

## Audience pattern (reuse for every new resource server)

`kian-coffee-web` tokens carry `aud=api.blog` via:
1. a custom client scope **`api.blog-audience`** holding an `oidc-audience-mapper`
   (`included.client.audience = api.blog`);
2. that scope added to `kian-coffee-web`'s **defaultClientScopes**.

→ Onboarding a resource server = create `<app>-audience` scope + attach it to each caller's
default scopes. This is the template the onboarding generator emits (Stage 3).

## Config management

- **Source of truth:** realm-JSON seeds in `keycloak/base/realms/*.json`, **per cluster** —
  dev seeds carry dev hostnames + `localhost`; prod seeds carry prod hostnames. Secrets are
  `${ENV}` placeholders injected from the `keycloak-realm-secrets` ExternalSecret (BWS).
- **Apply mechanism (current):** `kc.sh start --import-realm` — ⚠️ **import-once**: imports
  only realms absent from the DB. After first boot the seeds are inert and git is never
  reconciled against the DB. (Replaced by keycloak-config-cli in Stage 2.)
- **Audit 2026-06-26:** a redacted live `partial-export` of all realms (dev **and** prod) was
  diffed against the git seeds → **no meaningful drift.** Every custom client, redirect URI,
  role, IdP, scope, and audience mapper matches git. The realm config was faithfully
  maintained as code; what was missing was a reconcile loop to guarantee it.

## Backups

- `keycloak-backup/realm-export-cronjob.yaml` — daily partial-export of all realms to the
  `keycloak-backups` PVC, 30-day retention.
- `keycloak-backup/db-backup-cronjob.yaml` — daily CNPG `pg_dump`, 7-day retention.

## Known cleanups (tracked)

- `kian-coffee` prod seed has duplicate redirect URIs (cosmetic — dedupe under config-cli).
- `broker-master` client in `accounts` is unused (master has no `accounts` IdP) — remove or wire.
- `kian-coffee` seeds are bloated full-realm exports — slim to managed fields under config-cli.
- `techgarden` realm + `bff`/`svc.profile` + `broker-techgarden` decommissioning (Stage 1).

_See the upgrade/management plan: `.ai/plans/tool-currency-upgrade/` and the Keycloak
tame-and-consolidate plan. config-cli reconcile = Stage 2; onboarding generator = Stage 3;
official-Operator + 26.6.4 upgrade = Stage 4._
