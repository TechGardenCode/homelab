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
                   |              \
         IdP "accounts"      IdP "accounts"   (master: broker client exists,
         hausparty          kian-coffee        IdP not wired → unused)
         hausparty          api.blog, kian-coffee-web
```

- **accounts** (hub) — users (`kian`, `techgardencode`), cross-realm roles (`infra-admin`,
  `app-admin`), one confidential `broker-<spoke>` client per spoke. Hardened: 14-char
  password policy, TOTP required, brute-force protection.
- **spokes** (`hausparty`, `kian-coffee`) — each has an `accounts` IdP (syncMode FORCE) + a
  hardcoded-role IdP mapper, plus its app clients. No local users.
- **master** — admin-console realm. A `broker-master` client exists in `accounts` but master
  has **no** `accounts` IdP, so `broker-master` is currently unused cruft; admin login uses
  the local bootstrap admin.

> **Realm = product/tenant boundary.** Homelab/internal apps share the hub's identity; each
> public product gets its own spoke realm (a spoke may host several app clients). New homelab
> app = a new client in an existing realm; new product = a new spoke realm. **Onboard either
> with the `add-keycloak-client` skill** (`.claude/skills/` in kian.sh) — it emits the client/
> realm JSON, audience scope, ExternalSecret key, config-cli env wiring, and BWS secret in one PR.

## Custom clients (Keycloak system clients omitted)

| Realm | Client | Type | Notes |
|---|---|---|---|
| accounts | `broker-{hausparty,kian-coffee,master}` | confidential | broker-in clients |
| hausparty | `hausparty` | confidential, std flow | NextAuth; redirect `hausparty.techgarden.gg/*` |
| kian-coffee | `kian-coffee-web` | public + PKCE | Angular SPA; redirect `kian.coffee/admin/blog` |
| kian-coffee | `api.blog` | confidential / bearer | resource server; tokens carry `aud=api.blog` |

## Audience pattern (reuse for every new resource server)

`kian-coffee-web` tokens carry `aud=api.blog` via:
1. a custom client scope **`api.blog-audience`** holding an `oidc-audience-mapper`
   (`included.client.audience = api.blog`);
2. that scope added to `kian-coffee-web`'s **defaultClientScopes**.

→ Onboarding a resource server = create `<app>-audience` scope + attach it to each caller's
default scopes. The `add-keycloak-client` skill emits this template (see §Audience there).

## Config management

- **Source of truth:** realm-JSON seeds in `keycloak/base/realms/*.json`, **per cluster** —
  dev seeds carry dev hostnames + `localhost`; prod seeds carry prod hostnames. Secrets use
  config-cli `$(env:NAME)` placeholders injected from the `keycloak-realm-secrets` ExternalSecret (BWS).
- **Apply mechanism:** **keycloak-config-cli** (`base/config-cli-job.yaml`, ArgoCD **PostSync
  hook**) reconciles the seeds into the running Keycloak via the Admin API on every sync — git
  is the *enforced* source of truth. All managed policies = `no-delete` (purely additive/update,
  never prunes — so minimal seeds can't drop Keycloak defaults). **Users are NOT managed**
  (stripped from seeds; they live in the DB + backups). Pinned
  `adorsys/keycloak-config-cli:6.5.1-26.1.0` (bump alongside the server in Stage 4).
- **Gotcha removed:** invalid `"openid"` entries in client `defaultClientScopes` were stripped —
  `--import-realm` silently ignored them, but config-cli does a strict client-scope lookup and
  NPEs on them.
- **Audit 2026-06-26:** a redacted live `partial-export` of all realms (dev **and** prod) was
  diffed against the git seeds → **no meaningful drift.** The realm config was faithfully
  maintained as code; what was missing was the reconcile loop — now provided by config-cli.

## Backups

- `keycloak-backup/realm-export-cronjob.yaml` — daily partial-export of all realms to the
  `keycloak-backups` PVC, 30-day retention.
- `keycloak-backup/db-backup-cronjob.yaml` — daily CNPG `pg_dump`, 7-day retention.

## Known cleanups (tracked)

- `kian-coffee` prod seed has duplicate redirect URIs (cosmetic — dedupe; config-cli will apply).
- `broker-master` client in `accounts` is unused (master has no `accounts` IdP) — remove or wire.
- `kian-coffee` seeds are bloated full-realm exports — slim to managed fields.
- broker/hausparty clients carry a cosmetic `"optionalClientScopes": null` (config-cli-safe).

> **Stage 1 done (2026-06-26):** `techgarden` realm + `broker-techgarden` client deleted live
> (dev + prod) and from git; dead techgarden app tree removed across 1276-prod / 1501-prod /
> 1276-dev + the ApplicationSet exclude. The never-running Bitnami keycloak went with it.
>
> **Stage 2 done (2026-06-26):** config-cli reconcile live on dev + prod; `--import-realm`
> dropped; users stripped from seeds (preserved in DB — verified); techgarden secret plumbing
> swept; OIDC healthy. Found & fixed the `openid` strict-lookup gotcha on dev before prod.
>
> **Stage 3 done (2026-06-26):** `add-keycloak-client` skill shipped (kian.sh `.claude/skills/`)
> — one-shot onboarding for spa / confidential / resource-server / m2m clients and new product
> realms. Templates derived from the live seeds; validated by jq-splice + `kustomize build`.
> Onboard friction is now ~5 min: edit seed(s) + wire one secret + dev dry-run + push.

_See the upgrade/management plan: `.ai/plans/tool-currency-upgrade/` and the Keycloak
tame-and-consolidate plan. config-cli reconcile = Stage 2 ✅; onboarding skill = Stage 3 ✅
(`add-keycloak-client`); official-Operator + 26.6.4 upgrade = Stage 4 (pending)._
