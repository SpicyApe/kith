# kith.app — marketing site

Static landing site for Kith, hosted on Cloudflare Pages at `kith.app`. Plain HTML/CSS, no build step, no JS framework — a few lines of vanilla JS handle the referral cookies on `p.html` and `c.html`.

## Deploying to Cloudflare Pages

1. Connect this repo in the Cloudflare dashboard (Pages → Create a project → Connect to Git), or use `wrangler pages deploy`.
2. Project settings:
   - **Root directory:** `web`
   - **Build command:** (none)
   - **Build output directory:** `/` (the root directory itself — there's nothing to build)
3. Set the custom domain to `kith.app` once the project is live.

`_redirects` and `_headers` are read automatically by Cloudflare Pages from the project root (i.e. `web/_redirects`, `web/_headers`); no extra configuration is needed for the `/p/*` and `/c/*` rewrites or the AASA content-type header.

## What to replace before launch

- **`.well-known/apple-app-site-association`** — `TEAMID.app.kith.ios` must become the real Apple Developer Team ID plus bundle identifier (e.g. `ABCDE12345.app.kith.ios`), so universal links (`kith.app/p/*`, `kith.app/c/*`) open the installed app. This file must be served with `Content-Type: application/json` (handled by `_headers`) and **no** file extension — do not rename it.
- **App Store badge links** — every `https://apps.apple.com/app/idPLACEHOLDER` (in `index.html`, `p.html`, `c.html`) must be replaced with the real App Store URL once the app has an App Store ID.
- **`privacy@kith.app`** in `privacy.html` and `terms.html` — replace if the real support/privacy contact address differs.
- **`[Jurisdiction]`** in `terms.html` — fill in the actual governing-law jurisdiction before launch.

## Referral cookies (`kith_ref` / `kith_circle`)

Per the attribution approach in `docs/05-launch-plan-and-roadmap.md` §4:

- `p.html` is the fallback for share links (`kith.app/p/<puzzle-number>?r=<code>`). If a universal link opens the installed app directly, this page is never seen. Otherwise, it reads the puzzle number and `r` query param from `location`, and — if `r` matches `/^[A-Z0-9]{4,12}$/i` — sets a first-party cookie: `kith_ref=<code>; Max-Age=2592000; Path=/; SameSite=Lax; Secure`.
- `c.html` is the fallback for circle invite links (`kith.app/c/<code>`). It sets `kith_circle=<code>` the same way, with the same validation and cookie attributes.
- **The iOS app never reads these cookies** — cookies set in Safari/web are not accessible to the native app. They exist purely so **web analytics** (page views, App Store click-throughs) can be attributed to a specific sender or circle before the visitor ever installs anything.
- On first launch, the app instead asks the user "Have a code?" and prefills it only if the user pastes one from their clipboard (deferred deep linking is intentionally not built — see `docs/05-launch-plan-and-roadmap.md` §4). The cookies set here are a web-side attribution signal only, not a mechanism for passing the code into the app.

## Files

| File | Purpose |
|---|---|
| `index.html` | Landing page |
| `p.html` | Share-link fallback (`/p/<number>?r=<code>`) |
| `c.html` | Circle-invite fallback (`/c/<code>`) |
| `privacy.html` | Privacy policy |
| `terms.html` | Terms of service |
| `style.css` | Shared stylesheet |
| `_redirects` | Cloudflare Pages rewrite rules for `/p/*` and `/c/*` |
| `_headers` | Content-Type/Cache-Control for the AASA file |
| `.well-known/apple-app-site-association` | Universal link config for iOS |
