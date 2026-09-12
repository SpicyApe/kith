# Kith — Deployment Runbook

Everything needed to go from this repo to a running backend, a website, and an
app on a phone. Written for a solo developer on Windows with an iPhone and no Mac;
the macOS steps run on GitHub Actions.

## 1. Supabase project

**Current project (created 2026-09-12):** ref `guesfztufvxeqylyjvyi`, region us-east-1,
URL `https://guesfztufvxeqylyjvyi.supabase.co`, dashboard
https://supabase.com/dashboard/project/guesfztufvxeqylyjvyi. All migrations are applied,
`CONTACT_PEPPER`, `KITH_SERVICE_ROLE_KEY` and `KITH_CRON_SECRET` are set, every function is
deployed, the Vault secrets exist and both cron jobs are scheduled, phone auth is enabled
with two test numbers (the owner's and `+1 500 555 0006` for CI, code `123456`, valid until
2027-01-01), and the GitHub secrets `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `KITH_TEST_PHONE` /
`KITH_TEST_OTP` are set. The database password, pepper and cron secret are in `~/.kith/` on
the machine that created the project. Still to do: real Twilio credentials before public
users, APNs secrets for pushes, and the owner's `admins` row after their first sign-in.

**Games hub (docs/07, deployed 2026-09-12):** migration 0006 applied, `submit-game` deployed,
`generate-puzzles` redeployed; `daily_games` holds Stars, Duo and Trail for 30 days through
2026-10-11. The grid-games fill pass is capped at 8 s per invocation because the edge runtime
killed a longer pass with `WORKER_RESOURCE_LIMIT`; the nightly cron tops up three games a day,
and a backfill is done by invoking the function repeatedly (cron-secret bearer + anon `apikey`)
until `games.created` comes back empty. The admin page does not yet show `daily_games`;
reseed one with `{"date":"YYYY-MM-DD","game":"stars"}` (409 `has_results` once anyone has played it).

1. Create a project at supabase.com. Note the project URL, anon key, and service-role key.
2. Enable phone auth: Authentication → Providers → Phone, with Twilio Verify credentials.
   Set OTP length 6, expiry 5 minutes.
3. Apply the schema. Either paste `supabase/migrations/0001_init.sql` into the SQL editor,
   or with the CLI: `supabase link --project-ref <ref>` then `supabase db push`.
   `pg_cron` must be enabled first: Database → Extensions → `pg_cron`, `pg_net`.
4. Seed content: applied by `supabase db push` as migration 0003 (idempotent). Lists are inserted
   with `enabled = false`; enable each one only after checking its values against the
   source links (Admin page → Lists).
5. Make yourself an admin. After you have signed up in the app once:
   ```sql
   insert into admins (user_id) select id from users where display_name = '<your name>';
   ```
6. Secrets for edge functions (Project Settings → Edge Functions → Secrets):

   | Secret | Value |
   |---|---|
   | `CONTACT_PEPPER` | 32+ random bytes, base64. Generate once, never rotate without a migration plan (rotating invalidates every stored HMAC). |
   | `APNS_KEY_ID` | Key ID of an APNs auth key (.p8) from the Apple developer portal |
   | `APNS_TEAM_ID` | Your Apple team ID |
   | `APNS_PRIVATE_KEY` | Contents of the .p8 file; newlines may be literal `\n` |
   | `APNS_BUNDLE_ID` | `app.kith.ios` |
   | `KITH_SERVICE_ROLE_KEY` | The legacy `service_role` JWT (Project Settings → API Keys → Legacy). The runtime injects an `sb_secret_…` key as `SUPABASE_SERVICE_ROLE_KEY`, but PostgREST rejects it until new API keys are enabled for the project, so the functions prefer this one. |
   | `KITH_CRON_SECRET` | Random string; pg_cron sends it as the bearer to `send-pushes` and `generate-puzzles` (see step 8) |

   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected automatically (the last one as an `sb_secret_…` key; see `KITH_SERVICE_ROLE_KEY`).
7. Deploy functions: `supabase functions deploy register submit-result match-contacts delete-account send-pushes generate-puzzles`.
   `send-pushes` and `generate-puzzles` must be deployed with `--no-verify-jwt` because pg_cron calls
   them with the service-role key rather than a user JWT (the functions verify the bearer themselves).
8. Cron. The two background functions are called by pg_cron with the anon key as
   `apikey` (for the functions gateway) and a dedicated random secret as the bearer.
   Set the secret on the functions (`supabase secrets set KITH_CRON_SECRET=<random>`),
   store three Vault secrets, and schedule:
   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
   select vault.create_secret('<anon key>', 'anon_key');
   select vault.create_secret('<KITH_CRON_SECRET value>', 'cron_secret');
   select public.schedule_background_jobs();
   ```
   Verify with `select jobname, schedule from cron.job;`. (The injected
   `SUPABASE_SERVICE_ROLE_KEY` in the edge runtime is an `sb_secret_…` key that the
   gateway refuses as a bearer, which is why a shared secret is used instead.)
9. First puzzles: open the Admin page, sign in, press **Generate 30 days**, review, approve.

## 2. Website (Cloudflare Pages)

Root directory `web`, no build command. Custom domain `kith.app`. Before publishing,
replace in `web/`: `TEAMID` in `.well-known/apple-app-site-association`, the App Store
id in every `idPLACEHOLDER` link, `[Jurisdiction]` in `terms.html`. Details in `web/README.md`.

## 3. Admin page

`admin/index.html` is a single static file. Fill `SUPABASE_URL` and `SUPABASE_ANON_KEY`
at the top and host it anywhere private (a second Cloudflare Pages project with
access restricted, or open it from disk). It signs in with your phone number and only
works for rows in `admins`.

## 4. iOS build without a Mac

The workflow `.github/workflows/ios.yml` builds on a macOS runner:

1. Push the repo to GitHub. Add repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`
   so the build embeds them in `Config.plist`.
2. Every push to `main` runs the two Swift package test suites and then produces the
   artifact **Kith-unsigned.ipa**.
3. Download the artifact, unzip it, and sign + install with 3uTools (Apps → Install, or
   the "IPA Signature" tool with your Apple ID). A free Apple ID gives a 7-day
   certificate; reinstall weekly, or use a paid developer account for a year.

What does not work on a free-ID sideload: push notifications (no `aps-environment`
entitlement) and universal links (no associated-domains entitlement). The app catches
the push registration error and continues; `kith://` links still work. Contacts,
puzzles, boards, circles, and sharing are unaffected.

If Apple's toolchain rejects something in the SwiftUI target, the fix loop is: read the
CI log, edit under `apps/ios/Kith/`, push. `apps/ios/Kith/README.md` lists the spots
the author was least sure of.

## 5. Automated testing

Every suite runs on GitHub Actions on each push to `main` and on pull requests. Nothing needs a Mac or a Supabase project.

| Workflow / job | Runner | What runs |
|---|---|---|
| Backend → Edge functions | ubuntu | `deno check` of every entrypoint, `deno test` (256 tests) |
| Backend → Schema + RLS + seed | ubuntu | pglite applies the migration, exercises policies and RPCs as real roles, loads the seed twice |
| iOS → Swift packages | macOS | `swift test` for LineupEngine, GridGames and KithCore |
| iOS → App unit + UI tests | macOS simulator | `KithTests` (14 in-process tests over an in-memory fake backend) and `KithUITests` (7 XCUITests through onboarding, play, board, circles, profile). Flaky-test retry is one extra iteration; a deterministic failure still fails. On failure the `.xcresult` is uploaded and the failure summary is printed. |
| iOS → Live end-to-end (real backend) | macOS simulator | `KithLiveTests`: launches the real app against the live Supabase project, signs in with the Supabase test number (secrets `KITH_TEST_PHONE` / `KITH_TEST_OTP`), registers, plays today's puzzle to a result, checks the board and profile, and deletes the account. Gated by the repository variable `KITH_LIVE_E2E` (currently `true`) or manual dispatch with `live=true`; serialized by a concurrency group. Failures print the app's status line (stage, step, last error) and the screen tree. |
| iOS → Unsigned IPA | macOS | Only after both iOS jobs pass |

The app-side test seam (`-uiTesting` launch argument, fake API states, accessibility identifiers) is specified in `apps/ios/TESTING.md`.

Locally on a Windows or Linux machine you can still run everything except the two simulator bundles:

| Suite | Command |
|---|---|
| Puzzle engine | `cd packages/LineupEngine && swift test` |
| Client core | `cd packages/KithCore && swift test` |
| Edge functions | `cd supabase/functions && deno test --allow-read` |
| Schema + RLS | `cd supabase/tests && npm install && npm test` |

## 6. Rotations and incidents

- **Pepper leaked**: stored HMACs become brute-forceable for anyone with the DB too. Rotate by
  setting a new `CONTACT_PEPPER`, truncating `contact_hashes` and `matches`, and forcing a full
  re-sync from every client (`ContactSyncPlanner` does a full sync when `lastSynced` is cleared);
  `users.phone_hmac` must be recomputed at next sign-in (`register` is idempotent, so add a
  one-off function to recompute from `auth.users.phone` with the service role).
- **APNs key revoked**: replace the four `APNS_*` secrets; no client change.
- **Bad puzzle shipped**: Admin → Reseed on that date; already-submitted results stay.
