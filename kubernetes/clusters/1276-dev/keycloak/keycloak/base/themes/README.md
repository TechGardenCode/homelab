# TechGarden Keycloak theme (`techgarden`)

Branded login + email theme for the dev `techgarden` realm at `sso.dev.techgarden.gg`.
Keycloak **26.6.3**. Workstream **WS-05**.

**This README travels with the theme into the homelab repo.** Keep it beside
`techgarden/`.

> ### If you are reading this in the `techgarden` app repo
>
> **This copy is in transit, and it is temporary.** WS-05's owner decided the theme's
> living home is the **homelab** repo, beside the Keycloak manifests — one copy, so there
> is nothing to drift. It sits here only because the alternative was worse: it was authored
> in `docs/superpowers/`, which is gitignored *and* inside a worktree the `/develop` loop
> deletes, so ~20 files of browser-proven work existed on exactly one machine and in no repo.
>
> **Delete `docs/cross-repo/ws-05-theme/` at Stage 3**, once the homelab PR has merged and
> the brief records the real path. Until then, treat it as frozen: if a design-system token
> changes, fix it in **homelab**, not here — a stale copy that nobody deletes is precisely
> the failure this workstream was shaped to avoid.
>
> The durable record that outlives this directory is
> [`../ws-05-keycloak-login-theme.md`](../ws-05-keycloak-login-theme.md).

## What it themes

Six live surfaces, all proven locally against a real `quay.io/keycloak/keycloak:26.6.3`
before handover:

| Surface | Template (inherited from `base`) |
|---|---|
| Sign in | `login.ftl` |
| Forgot password | `login-reset-password.ftl` |
| "Check your email" | `info.ftl` |
| Set a password | `login-update-password.ftl` — also the `UPDATE_PASSWORD` required action used for hand-provisioning |
| Verify email | `login-verify-email.ftl` |
| Error | `error.ftl` |

Plus the transactional emails: **password reset**, **verify email**, and the
**account invite** (`execute-actions-email`, the flow WS-04 proved).

**Not registration.** Per ADR-0052 there is no self-service signup; `register.ftl` is
never reached.

## How it is built

- **`parent=base`, raw FreeMarker.** At 26.6.3 the stock `keycloak` theme contains
  zero `.ftl` files — every template lives in `base`, and `keycloak` adds only
  PatternFly CSS. Inheriting `base` gives every template with no stylesheet to fight.
- **`login/` overrides no `.ftl` at all.** Everything is done through `theme.properties`
  class bindings plus one stylesheet, so a Keycloak upgrade that changes template markup
  cannot leave a stale copy of it here.
- **`email/` overrides four**: the shared `html/template.ftl` layout macro (which brands
  every email at once) and three templates that need a real CTA button — the button lives
  in markup because message HTML passes through `kcSanitize()`, which may strip the inline
  styles an email button is made of.
- **Zero outbound requests.** No Google Fonts, no CDN, no icon font. Verified in a browser:
  every request on the login page is same-origin. Fonts are self-hosted woff2; the two
  icons are inline SVG data URIs.

```
techgarden/
├── login/
│   ├── theme.properties          # parent=base, styles=, kc*Class -> .tg-* bindings
│   ├── messages/messages_en.properties
│   └── resources/
│       ├── css/login.css         # the only authored CSS
│       ├── fonts/                # 4 woff2 + 2 OFL licence texts
│       └── img/                  # logo.png, favicon.ico
└── email/
    ├── theme.properties          # parent=base
    ├── messages/messages_en.properties
    └── html/                     # template.ftl (layout) + 3 CTA overrides
```

Total ≈ 210 KB, dominated by the font binaries.

## Wiring it up

Two realm fields on the dev `techgarden` realm:

```json
"loginTheme": "techgarden",
"emailTheme": "techgarden"
```

The theme directory must be readable by the Keycloak process at
**`/opt/keycloak/themes/techgarden/`**.

**Mounting is safe at that path** — verified: `/opt/keycloak/themes/` in the
`quay.io/keycloak/keycloak:26.6.3` image contains only a `README.md`. The built-in
`base`, `keycloak` and `keycloak.v2` themes ship *inside jars*
(`/opt/keycloak/lib/lib/main/org.keycloak.keycloak-themes-26.6.3.jar`), so a volume here
shadows nothing and `parent=base` keeps resolving.

**A theme change needs a pod restart.** In production mode Keycloak caches themes and
templates (`cacheThemes`/`cacheTemplates` default true, `staticMaxAge` 30 days). Editing
files in place — or editing a ConfigMap, which the operator does not watch — does not take
effect until the pods roll.

## Iterating on it

Run it against real Keycloak; do not eyeball it:

```sh
docker run --rm -p 8088:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  -v "$PWD/techgarden:/opt/keycloak/themes/techgarden:ro" \
  quay.io/keycloak/keycloak:26.6.3 start-dev
```

`start-dev` disables the theme and template caches, so edits show up on reload.
Then create a realm with `loginTheme=techgarden`, a public client, and a user. To see the
emails, point the realm's SMTP at a catcher (`axllent/mailpit`, host port 1025).

**Two traps worth knowing before you edit copy:**

1. **Some message keys are shared across pages.** `doSubmit` renders the primary button on
   *both* `login-reset-password.ftl` and `login-update-password.ftl` — wording that suits
   one can be nonsense on the other. Check every surface after changing a generic key.
2. **`'` is MessageFormat's quote character.** In any string that also contains a `{0}`
   placeholder it must be doubled (`''`) or the placeholder silently stops substituting.

## Keeping it in sync with the design system

`login.css` carries **literal copies** of a subset of the TechGarden design system, because
Keycloak lives in a different repo and a different origin and can neither import that CSS
nor share a stylesheet with the app.

The app repo (`TechGardenCode/techgarden`) carries the callback: see **"Downstream consumers
outside this repo"** in `design-system/README.md`, which lists exactly which changes there
mean this theme needs checking. Every copied block in `login.css` names its source file in a
comment.

Only the subset a login page uses is copied. **This is not a mirror of the design system and
must not grow into one.**

## Licence

The two font families are SIL Open Font License 1.1, redistributed unmodified. OFL 1.1
requires the licence and copyright notice accompany every copy, so
`OFL-bricolage-grotesque.txt` and `OFL-hanken-grotesk.txt` ship beside the binaries in
`login/resources/fonts/` and are served by Keycloak. **Do not remove them.**
