# Kith — Deployment Runbook

Everything needed to go from this repo to a running backend, a website, and an
app on a phone. Written for a solo developer on Windows with an iPhone and no Mac;
the macOS steps run on GitHub Actions.

## 1. Supabase project

1. Create a project at supabase.com. Note the project URL, anon key, and service-role key.
2. Enable phone auth: Authentication → Providers → Phone, with Twilio Verify credentials.
   Set OTP length 6, expiry 5 minutes.
3. Apply the schema. Either paste `supabase/migrations/0001_init.sql` into the SQL editor,
   or with the CLI: `supabase link --project-ref <ref>` then `supabase db push`.
   `pg_cron` must be enabled first: Database → Extensions → `pg_cron`, `pg_net`.
4. Seed content: run `supabase/seed/content.sql` in the SQL editor. Lists are inserted
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

   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.
7. Deploy functions: `supabase functions deploy register submit-result match-contacts delete-account send-pushes generate-puzzles`.
   `send-pushes` and `generate-puzzles` must be deployed with `--no-verify-jwt` because pg_cron calls
   them with the service-role key rather than a user JWT (the functions verify the bearer themselves).
8. Cron. Store two Vault secrets, then apply `supabase/migrations/0002_cron.sql`:
   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
   select vault.create_secret('<service role key>', 'service_role_key');
   ```
   Verify with `select * from cron.job;`.
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

## 5. Local verification (what runs on this Windows machine)

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
