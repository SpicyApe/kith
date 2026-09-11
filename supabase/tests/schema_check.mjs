process.on("unhandledRejection",e=>{console.error("FAILED:",e.message||e);process.exit(1)});
import { PGlite } from "@electric-sql/pglite";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import fs from "node:fs";

const db = new PGlite({ extensions: { pgcrypto } });
const sql = fs
  .readFileSync(new URL("../migrations/0001_init.sql", import.meta.url), "utf8")
  .replace("create extension if not exists pg_cron;", "");

await db.exec(`
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('app.uid', true), '')::uuid $$;
  -- Supabase's real roles. The migration's policies/grants reference them
  -- ("to authenticated", "revoke ... from anon"), so they must exist first.
  create role anon nologin;
  create role authenticated nologin;
  -- The migration grants EXECUTE on a few functions to service_role (the role
  -- edge functions connect as); it must exist before the migration runs. pglite
  -- applies the migration as its own superuser regardless of this role's
  -- privileges, so creating it here is enough.
  create role service_role nologin;
`);
await db.exec(sql);
console.log("migration: OK");

const A = "11111111-1111-1111-1111-111111111111";
const B = "22222222-2222-2222-2222-222222222222";
const C = "33333333-3333-3333-3333-333333333333";
const D = "44444444-4444-4444-4444-444444444444"; // isolated: no matches, no circle, used for negative checks
const today = new Date().toISOString().slice(0, 10);
const yest = new Date(Date.now() - 86400e3).toISOString().slice(0, 10);
const twoAgo = new Date(Date.now() - 2 * 86400e3).toISOString().slice(0, 10);

await db.exec(`
  insert into auth.users values ('${A}'),('${B}'),('${C}'),('${D}');
  insert into public.users (id, phone_hmac, display_name) values
    ('${A}','ha','Alex'),('${B}','hb','Sam'),('${C}','hc','Casey'),('${D}','hd','Dana');
  insert into public.matches (user_a, user_b, mutual) values
    ('${A}','${B}', true), ('${A}','${C}', false);
  insert into public.lists (prompt_template, unit, direction) values ('Order by year', 'year', 'Earliest at the top');
  insert into public.list_items (list_id, label, value, source_url, familiarity) values
    (1,'Bicycle',1817,'u',1),(1,'Telephone',1876,'u',1),(1,'Light bulb',1879,'u',1),(1,'Zipper',1913,'u',2),(1,'Microwave',1946,'u',1);
  insert into public.puzzles (date, number, list_id, item_ids, correct_order, status, difficulty) values
    ('${twoAgo}', 140, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'approved', 'easy'),
    ('${yest}',   141, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'approved', 'easy'),
    ('${today}',  142, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'approved', 'easy');
  insert into public.results (user_id, puzzle_date, attempts, tries, solved, elapsed_ms, score, tz) values
    ('${A}','${twoAgo}','[]',1,true,30000,940,'UTC'),
    ('${A}','${yest}','[]',2,true,48210,604,'UTC'),
    ('${B}','${yest}','[]',1,true,20000,960,'UTC'),
    ('${A}','${today}','[]',1,true,40000,920,'UTC'),
    ('${B}','${today}','[]',3,false,90000,100,'UTC'),
    ('${C}','${today}','[]',1,true,10000,980,'UTC'),
    ('${D}','${today}','[]',1,true,15000,970,'UTC');
`);
console.log("seed: OK");

await db.exec(`set app.uid = '${A}'`);
const board = await db.query(`select display_name, score, played, rank, prev_rank from public.board('friends', null, 'today', '${today}')`);
console.table(board.rows);
const names = board.rows.map((r) => r.display_name);
if (!(names.includes("Alex") && names.includes("Sam") && !names.includes("Casey"))) throw new Error("friends board should be Alex+Sam only");
const alex = board.rows.find((r) => r.display_name === "Alex");
if (alex.rank !== 1 || alex.prev_rank !== 2) throw new Error(`Alex rank/prev_rank wrong: ${JSON.stringify(alex)}`);

const week = await db.query(`select display_name, score, rank from public.board('friends', null, 'week', '${today}')`);
console.table(week.rows);

const streak = await db.query(`select public.streak('${A}') as a, public.streak('${B}') as b, public.streak('${C}') as c`);
console.log("streaks", streak.rows[0]);
if (streak.rows[0].a !== 3 || streak.rows[0].b !== 2 || streak.rows[0].c !== 1) throw new Error("streak mismatch");

// circles: owner auto-joins; join by code (>= 6 chars, uppercase alnum per circles_code_fmt);
// membership makes can_see true.
await db.exec(`insert into public.circles (code, name, owner_id) values ('ABC123', 'Family', '${A}')`);
await db.exec(`set app.uid = '${C}'`);
const joined = await db.query(`select public.join_circle('kith-abc123') as id`);
console.log("join_circle:", joined.rows[0].id ? "OK" : "FAIL");
const cb = await db.query(`select display_name, rank from public.board('circle', (select id from public.circles where code='ABC123'), 'today', '${today}')`);
console.table(cb.rows);
if (cb.rows.length !== 2) throw new Error("circle board should have 2 rows");

// RLS as a non-superuser role. `app` is a member of `authenticated`, so it inherits
// every grant the migration made "to authenticated" (and none of what it revoked).
await db.exec(`
  create role app in role authenticated;
  grant usage on schema public to app;
  grant select, insert, update, delete on all tables in schema public to app;
  grant usage, select on all sequences in schema public to app;
  -- NOT "grant execute on all functions ...": that would blanket-grant execute on
  -- the arbitrary-uuid can_see/streak/friend_ids too, defeating the migration's
  -- revokes (a direct grant to app isn't overridden by a revoke on a different
  -- role). Mirror exactly what the migration grants authenticated.
  grant execute on function
    public.can_see(uuid),
    public.my_streak(),
    public.is_circle_member(uuid),
    public.board(text, uuid, text, date),
    public.join_circle(text),
    public.track(text, jsonb),
    public.hide_taunt(uuid, date)
  to app;
  -- Same reasoning for users: the blanket table grant above re-opens every column,
  -- so narrow it back down the way the migration does for authenticated.
  revoke select, update on public.users from app;
  grant select (id, display_name, tz, discoverable, invite_code, created_at, last_open_at)
    on public.users to app;
  grant update (display_name, tz, discoverable, last_open_at) on public.users to app;
  set role app;
  set app.uid = '${B}';
`);
const seen = await db.query(`select user_id from public.results where puzzle_date = '${today}'`);
const seenIds = seen.rows.map((r) => r.user_id).sort();
console.log("B sees results of:", seenIds);
if (JSON.stringify(seenIds) !== JSON.stringify([A, B].sort())) throw new Error("RLS: B should see A and B only");
const hidden = await db.query(`select count(*)::int as n from public.contact_hashes`);
if (hidden.rows[0].n !== 0) throw new Error("RLS: contact_hashes must be invisible");
const puzzles = await db.query(`select number from public.puzzles order by number`);
console.log("B sees puzzles:", puzzles.rows.map((r) => r.number));
let taunted = false;
try {
  await db.query(`insert into public.taunts (user_id, puzzle_date, text) values ('${B}', '${today}', 'gg')`);
  taunted = true;
} catch (e) { console.log("taunt insert failed unexpectedly:", e.message); }
if (!taunted) throw new Error("B played today and should be able to taunt");

// D is a stranger to B (no match, no shared circle) — reacting to D must be refused.
let reactedToStranger = false;
try {
  await db.query(`insert into public.reactions (from_user, to_user, puzzle_date, emoji) values ('${B}', '${D}', '${today}', '🔥')`);
  reactedToStranger = true;
} catch (e) { console.log("reaction to non-visible user correctly refused:", e.message.split("\n")[0]); }
if (reactedToStranger) throw new Error("RLS: B must not react to D");

// users.phone_hmac: never selectable or updatable by an authenticated client.
let phoneReadable = true;
try {
  await db.query(`select phone_hmac from public.users limit 1`);
} catch (e) { phoneReadable = false; console.log("phone_hmac select correctly denied:", e.message.split("\n")[0]); }
if (phoneReadable) throw new Error("RLS: phone_hmac must not be selectable");

let phoneWritable = true;
try {
  await db.query(`update public.users set phone_hmac = 'x' where id = '${B}'`);
} catch (e) { phoneWritable = false; console.log("phone_hmac update correctly denied:", e.message.split("\n")[0]); }
if (phoneWritable) throw new Error("RLS: phone_hmac must not be updatable");

await db.query(`update public.users set display_name = 'Sam2' where id = '${B}'`);
const renamed = await db.query(`select display_name from public.users where id = '${B}'`);
if (renamed.rows[0].display_name !== "Sam2") throw new Error("RLS: display_name update should have succeeded");

// The arbitrary-uuid forms must never be directly executable, even by an authenticated caller.
let canSee2ArgAllowed = true;
try {
  await db.query(`select public.can_see('${C}', '${D}')`);
} catch (e) { canSee2ArgAllowed = false; console.log("2-arg can_see correctly denied:", e.message.split("\n")[0]); }
if (canSee2ArgAllowed) throw new Error("RLS: 2-arg can_see(uuid, uuid) must not be directly executable");

let friendIdsAllowed = true;
try {
  await db.query(`select * from public.friend_ids('${C}')`);
} catch (e) { friendIdsAllowed = false; console.log("friend_ids correctly denied:", e.message.split("\n")[0]); }
if (friendIdsAllowed) throw new Error("RLS: friend_ids(uuid) must not be directly executable");

// Now have B actually join the circle (as B would through the app) and check the
// circle/circle_members policies. Do this only after the checks above, since it
// makes B and C circle-mates (mutually can_see afterward).
const bJoined = await db.query(`select public.join_circle('kith-abc123') as id`);
if (!bJoined.rows[0].id) throw new Error("B should be able to join the circle");
const bRoster = await db.query(`select user_id from public.circle_members`);
console.log("B sees circle_members rows:", bRoster.rows.length);
if (bRoster.rows.length !== 3) throw new Error(`RLS: B should see all 3 members of its circle, got ${bRoster.rows.length}`);
const bCircleRow = await db.query(`select code from public.circles`);
if (bCircleRow.rows.length !== 1) throw new Error("RLS: B should see its own circle row");

// D shares no circle with anyone and must see zero circle_members rows.
await db.exec(`set app.uid = '${D}'`);
const dRoster = await db.query(`select circle_id from public.circle_members`);
if (dRoster.rows.length !== 0) throw new Error(`RLS: D shares no circle and should see 0 circle_members rows, got ${dRoster.rows.length}`);

await db.exec(`reset role`);

// A truly anonymous caller (the `anon` role, not a member of `authenticated`) must
// not be able to call board() at all — everyone board included.
await db.exec(`
  create role app_anon in role anon;
  grant usage on schema public to app_anon;
  set role app_anon;
  set app.uid = '';
`);
let anonBoardRows = 0;
try {
  const r = await db.query(`select * from public.board('everyone', null, 'today', '${today}')`);
  anonBoardRows = r.rows.length;
  console.log("anon board() unexpectedly returned rows:", anonBoardRows);
} catch (e) {
  console.log("anon board() correctly denied:", e.message.split("\n")[0]);
}
if (anonBoardRows > 0) throw new Error("RLS: anon must not see the everyone board");
await db.exec(`reset role`);

// ---------------------------------------------------------------------------
// recompute_matches (superuser / service-role context)
// ---------------------------------------------------------------------------
// Seed contact_hashes: A has B and C; B has A; C does not have A; D has A (but
// A does not have D). contact_hmac values must equal the target's phone_hmac
// from the users seed above (ha/hb/hc/hd).
await db.exec(`
  insert into public.contact_hashes (owner_id, contact_hmac) values
    ('${A}', 'hb'), ('${A}', 'hc'),
    ('${B}', 'ha'),
    ('${D}', 'ha');
`);
await db.query(`select public.recompute_matches('${A}')`);
const mAB1 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${B}'::uuid) and user_b = greatest('${A}'::uuid, '${B}'::uuid)`);
if (mAB1.rows.length !== 1 || mAB1.rows[0].mutual !== true) {
  throw new Error(`recompute_matches: expected A-B mutual=true, got ${JSON.stringify(mAB1.rows)}`);
}
const mAC1 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${C}'::uuid) and user_b = greatest('${A}'::uuid, '${C}'::uuid)`);
if (mAC1.rows.length !== 1 || mAC1.rows[0].mutual !== false) {
  throw new Error(`recompute_matches: expected A-C mutual=false, got ${JSON.stringify(mAC1.rows)}`);
}
const mAD1 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${D}'::uuid) and user_b = greatest('${A}'::uuid, '${D}'::uuid)`);
if (mAD1.rows.length !== 1 || mAD1.rows[0].mutual !== false) {
  throw new Error(`recompute_matches: expected A-D mutual=false, got ${JSON.stringify(mAD1.rows)}`);
}
console.log("recompute_matches: A-B mutual, A-C and A-D one-sided - OK");

// C opts out of discoverability: the A-C row should disappear on recompute.
await db.exec(`update public.users set discoverable = false where id = '${C}'`);
await db.query(`select public.recompute_matches('${A}')`);
const mAC2 = await db.query(
  `select 1 from public.matches where user_a = least('${A}'::uuid, '${C}'::uuid) and user_b = greatest('${A}'::uuid, '${C}'::uuid)`);
if (mAC2.rows.length !== 0) throw new Error("recompute_matches: A-C row should be deleted once C is not discoverable");
console.log("recompute_matches: A-C row deleted after C goes non-discoverable - OK");

// B removes A from their contacts: A-B should flip to not mutual.
await db.exec(`delete from public.contact_hashes where owner_id = '${B}' and contact_hmac = 'ha'`);
await db.query(`select public.recompute_matches('${B}')`);
const mAB2 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${B}'::uuid) and user_b = greatest('${A}'::uuid, '${B}'::uuid)`);
if (mAB2.rows.length !== 1 || mAB2.rows[0].mutual !== false) {
  throw new Error(`recompute_matches: expected A-B mutual=false after B drops A, got ${JSON.stringify(mAB2.rows)}`);
}
console.log("recompute_matches: A-B mutual=false after B drops A - OK");

// ---------------------------------------------------------------------------
// users_discoverable_changed trigger
// ---------------------------------------------------------------------------
// Restore B -> A so A-B is mutual again, giving the discoverable toggle below
// something to actually flip.
await db.exec(`insert into public.contact_hashes (owner_id, contact_hmac) values ('${B}', 'ha')`);
await db.query(`select public.recompute_matches('${B}')`);
const mAB3 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${B}'::uuid) and user_b = greatest('${A}'::uuid, '${B}'::uuid)`);
if (mAB3.rows.length !== 1 || mAB3.rows[0].mutual !== true) {
  throw new Error(`discoverable trigger setup: expected A-B mutual=true before the toggle, got ${JSON.stringify(mAB3.rows)}`);
}

// A turns discoverability off: the trigger must delete A's contact_hashes and
// immediately recompute. With A's hashes gone and A no longer discoverable,
// recompute_matches finds no edge in either direction and drops the A-B row
// entirely (the same "no edge left" behaviour as the C-opts-out case above),
// so A-B is no longer mutual right away, instead of waiting for B's next sync.
await db.query(`update public.users set discoverable = false where id = '${A}'`);
const mAB4 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${B}'::uuid) and user_b = greatest('${A}'::uuid, '${B}'::uuid)`);
if (mAB4.rows.length !== 0) {
  throw new Error(`users_discoverable_changed: expected the A-B row to be gone (no longer mutual) after A goes non-discoverable, got ${JSON.stringify(mAB4.rows)}`);
}
const aHashesAfterOptOut = await db.query(`select count(*)::int as n from public.contact_hashes where owner_id = '${A}'`);
if (aHashesAfterOptOut.rows[0].n !== 0) throw new Error("users_discoverable_changed: A's contact_hashes should be deleted after opting out");
console.log("users_discoverable_changed: A-B mutual=false and A's contact_hashes deleted after A opts out - OK");

// A opts back in, re-uploads contacts, and recomputes: mutual should return.
await db.exec(`update public.users set discoverable = true where id = '${A}'`);
await db.exec(`insert into public.contact_hashes (owner_id, contact_hmac) values ('${A}', 'hb'), ('${A}', 'hc')`);
await db.query(`select public.recompute_matches('${A}')`);
const mAB5 = await db.query(
  `select mutual from public.matches where user_a = least('${A}'::uuid, '${B}'::uuid) and user_b = greatest('${A}'::uuid, '${B}'::uuid)`);
if (mAB5.rows.length !== 1 || mAB5.rows[0].mutual !== true) {
  throw new Error(`users_discoverable_changed: expected A-B mutual=true again after A opts back in, got ${JSON.stringify(mAB5.rows)}`);
}
console.log("users_discoverable_changed: A-B mutual=true again after A opts back in - OK");

// ---------------------------------------------------------------------------
// start_puzzle
// ---------------------------------------------------------------------------
await db.exec(`set role app; set app.uid = '${B}';`);
const started = await db.query(`select public.start_puzzle('${today}') as p`);
const puzzleJson = started.rows[0].p;
if (puzzleJson.number !== 142) throw new Error(`start_puzzle: expected number 142, got ${JSON.stringify(puzzleJson.number)}`);
if (!Array.isArray(puzzleJson.items) || puzzleJson.items.length !== 5) {
  throw new Error(`start_puzzle: expected 5 items, got ${JSON.stringify(puzzleJson.items)}`);
}
const gotItemIds = puzzleJson.items.map((i) => i.id);
if (JSON.stringify(gotItemIds) !== JSON.stringify([1, 2, 3, 4, 5])) {
  throw new Error(`start_puzzle: items not in item_ids order: ${JSON.stringify(gotItemIds)}`);
}
const gotLabels = puzzleJson.items.map((i) => i.label);
if (JSON.stringify(gotLabels) !== JSON.stringify(["Bicycle", "Telephone", "Light bulb", "Zipper", "Microwave"])) {
  throw new Error(`start_puzzle: item labels wrong: ${JSON.stringify(gotLabels)}`);
}
if (JSON.stringify(puzzleJson.correctOrder) !== JSON.stringify([1, 2, 3, 4, 5])) {
  throw new Error(`start_puzzle: correctOrder wrong: ${JSON.stringify(puzzleJson.correctOrder)}`);
}
for (const it of puzzleJson.items) {
  if (Object.hasOwn(it, "value") || Object.hasOwn(it, "fact")) {
    throw new Error(`start_puzzle: items must not expose value/fact, got ${JSON.stringify(it)}`);
  }
}
console.log("start_puzzle: number/items/correctOrder, no value/fact leak - OK");

await db.exec(`reset role`);
const starts1 = await db.query(`select started_at from public.puzzle_starts where user_id = '${B}' and puzzle_date = '${today}'`);
if (starts1.rows.length !== 1) throw new Error(`start_puzzle: expected one puzzle_starts row for B/today, got ${starts1.rows.length}`);
const startedAt1 = new Date(starts1.rows[0].started_at).getTime();

// Calling again must not touch started_at or insert a second row.
await db.exec(`set role app; set app.uid = '${B}';`);
await db.query(`select public.start_puzzle('${today}') as p`);
await db.exec(`reset role`);
const starts2 = await db.query(`select started_at from public.puzzle_starts where user_id = '${B}' and puzzle_date = '${today}'`);
if (starts2.rows.length !== 1) throw new Error(`start_puzzle: expected still exactly one puzzle_starts row, got ${starts2.rows.length}`);
if (new Date(starts2.rows[0].started_at).getTime() !== startedAt1) throw new Error("start_puzzle: started_at changed on repeat call");
console.log("start_puzzle: repeat call is idempotent (started_at unchanged, one row) - OK");

// puzzle_starts already has a row for B (from start_puzzle above); seed a
// contact_sync_log row too so the invisibility check below isn't vacuous.
await db.exec(`insert into public.contact_sync_log (user_id, hashes, is_full) values ('${B}', 3, false)`);

// Neither table has client policies: app must see 0 rows, and a delete must
// silently match 0 rows rather than erroring or actually removing anything.
await db.exec(`set role app; set app.uid = '${B}';`);
const puzzleStartsHidden = await db.query(`select * from public.puzzle_starts`);
if (puzzleStartsHidden.rows.length !== 0) throw new Error("RLS: puzzle_starts must be invisible to clients");
const syncLogHidden = await db.query(`select * from public.contact_sync_log`);
if (syncLogHidden.rows.length !== 0) throw new Error("RLS: contact_sync_log must be invisible to clients");
const delPuzzleStarts = await db.query(`delete from public.puzzle_starts`);
const deletedCount = delPuzzleStarts.affectedRows ?? delPuzzleStarts.rows.length;
if (deletedCount !== 0) throw new Error(`RLS: delete from puzzle_starts should affect 0 rows for app, got ${deletedCount}`);
let recomputeAsAppThrew = false;
try {
  await db.query(`select public.recompute_matches('${A}')`);
} catch (e) {
  recomputeAsAppThrew = true;
  console.log("recompute_matches as app correctly denied:", e.message.split("\n")[0]);
}
if (!recomputeAsAppThrew) throw new Error("RLS: recompute_matches must not be callable by app");
await db.exec(`reset role`);
console.log("RLS: puzzle_starts/contact_sync_log invisible to app; delete matched 0 rows - OK");

// Confirm app's delete above really didn't remove anything.
const starts1b = await db.query(`select started_at from public.puzzle_starts where user_id = '${B}' and puzzle_date = '${today}'`);
if (starts1b.rows.length !== 1) throw new Error("app's no-op delete on puzzle_starts should not have removed the row");

// Outside the +/-14h window it must throw, even for a registered caller.
await db.exec(`set role app; set app.uid = '${B}';`);
let outsideWindowThrew = false;
try {
  await db.query(`select public.start_puzzle('2000-01-01') as p`);
} catch (e) {
  outsideWindowThrew = true;
  console.log("start_puzzle outside window correctly threw:", e.message.split("\n")[0]);
}
if (!outsideWindowThrew) throw new Error("start_puzzle: expected a throw for a date outside the +/-14h window");
await db.exec(`reset role`);

// A puzzle that exists for an in-window date but is still 'pending' (not yet
// approved) must be treated the same as no puzzle at all.
const win = await db.query(`
  select ((now() - interval '14 hours') at time zone 'UTC')::date::text as lo,
         ((now() + interval '14 hours') at time zone 'UTC')::date::text as hi`);
const usedDates = new Set([twoAgo, yest, today]);
const pendingDate = [win.rows[0].lo, win.rows[0].hi].find((d) => !usedDates.has(d));
if (!pendingDate) throw new Error("could not find a free in-window date for the pending-puzzle test");
await db.exec(`
  insert into public.puzzles (date, number, list_id, item_ids, correct_order, status, difficulty) values
    ('${pendingDate}', 999, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'pending', 'easy');
`);
await db.exec(`set role app; set app.uid = '${B}';`);
let pendingThrew = false;
try {
  await db.query(`select public.start_puzzle('${pendingDate}') as p`);
} catch (e) {
  pendingThrew = true;
  console.log("start_puzzle for a pending (unapproved) puzzle correctly threw:", e.message.split("\n")[0]);
}
if (!pendingThrew) throw new Error("start_puzzle: expected a throw for a pending (not yet approved) puzzle");
await db.exec(`reset role`);

// The anon role has no EXECUTE grant on start_puzzle at all.
await db.exec(`reset role`);
await db.exec(`set role anon; set app.uid = '';`);
let anonStartThrew = false;
try {
  await db.query(`select public.start_puzzle('${today}') as p`);
} catch (e) {
  anonStartThrew = true;
  console.log("start_puzzle as anon correctly threw:", e.message.split("\n")[0]);
}
if (!anonStartThrew) throw new Error("start_puzzle: expected a throw when called as anon");
await db.exec(`reset role`);

// ---------------------------------------------------------------------------
// service_role grants
// ---------------------------------------------------------------------------
// The blanket `revoke all ... from public` in the migration's Grants section
// strips the default PUBLIC EXECUTE grant; edge functions call these RPCs as
// service_role, so they must have been explicitly re-granted execute.
await db.exec(`set role service_role;`);
await db.query(`select public.recompute_matches('${A}')`);
await db.query(`select public.streak('${A}')`);
const su = await db.query(`select * from public.sync_usage('${A}', now() - interval '1 day')`);
console.log("service_role sync_usage:", su.rows[0]);
await db.exec(`reset role`);
console.log("service_role: recompute_matches/streak/sync_usage all callable - OK");

console.log("\nALL SCHEMA CHECKS PASSED");
