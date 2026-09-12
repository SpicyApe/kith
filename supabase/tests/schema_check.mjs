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
const tomorrow = new Date(Date.now() + 86400e3).toISOString().slice(0, 10);

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
  grant select (id, display_name, tz, discoverable, invite_code, created_at, last_open_at,
                push_daily, push_daily_at, push_streak, push_passed)
    on public.users to app;
  grant update (display_name, tz, discoverable, last_open_at,
                push_daily, push_daily_at, push_streak, push_passed)
    on public.users to app;
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
// Deterministic regardless of the time of day: take the upper in-window date and,
// if the seed already has a puzzle there, flip it to pending for the duration of
// the check; otherwise insert a pending one. Restore afterwards.
const pendingDate = win.rows[0].hi;
const pendingExisting = await db.query(`select status from public.puzzles where date = '${pendingDate}'`);
if (pendingExisting.rows.length > 0) {
  await db.exec(`update public.puzzles set status = 'pending' where date = '${pendingDate}'`);
} else {
  await db.exec(`
    insert into public.puzzles (date, number, list_id, item_ids, correct_order, status, difficulty) values
      ('${pendingDate}', 999, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'pending', 'easy');
  `);
}
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
if (pendingExisting.rows.length > 0) {
  await db.exec(`update public.puzzles set status = '${pendingExisting.rows[0].status}' where date = '${pendingDate}'`);
} else {
  await db.exec(`delete from public.puzzles where date = '${pendingDate}'`);
}

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

// ---------------------------------------------------------------------------
// push_candidates
// ---------------------------------------------------------------------------
// NOTE on clock values: `push_candidates(at)` uses a *forward* 15-minute
// window [at, at+15min) against each local target time (push_daily_at, or
// the fixed 20:00 for streak_risk) — i.e. a target matches when
// `at` <= target < at+15min, so `at` must land at-or-before the target
// (within the preceding 15 minutes), never after it. Calling 5 minutes
// *after* a target (e.g. 08:05Z for an 08:00 target) never matches. The
// checks below call `push_candidates` exactly at each target time, which is
// always inside its own window.
await db.exec(`
  insert into public.devices (user_id, apns_token, env) values
    ('${A}', 'tokA', 'sandbox'),
    ('${B}', 'tokB', 'sandbox');
  update public.users set push_daily_at = '08:00' where id = '${A}';
`);

const daily1 = await db.query(
  `select user_id, kind, payload from public.push_candidates('${today}T08:00:00Z') where user_id = '${A}'`,
);
if (daily1.rows.length !== 1 || daily1.rows[0].kind !== "daily_drop") {
  throw new Error(`push_candidates: expected one daily_drop row for A at 08:00Z, got ${JSON.stringify(daily1.rows)}`);
}
if (typeof daily1.rows[0].payload.friendsPlayed !== "number") {
  throw new Error(`push_candidates: payload.friendsPlayed should be a number, got ${JSON.stringify(daily1.rows[0].payload)}`);
}
console.log("push_candidates: daily_drop fires for A at push_daily_at - OK");

const daily2 = await db.query(
  `select user_id from public.push_candidates('${today}T07:30:00Z') where user_id = '${A}'`,
);
if (daily2.rows.length !== 0) throw new Error(`push_candidates: expected no row for A at 07:30Z, got ${JSON.stringify(daily2.rows)}`);
console.log("push_candidates: no daily_drop for A well before its window - OK");

await db.exec(`insert into public.notification_log (user_id, kind) values ('${A}', 'daily_drop')`);
const daily3 = await db.query(
  `select user_id from public.push_candidates('${today}T08:00:00Z') where user_id = '${A}' and kind = 'daily_drop'`,
);
if (daily3.rows.length !== 0) throw new Error(`push_candidates: expected no repeat daily_drop for A once logged today, got ${JSON.stringify(daily3.rows)}`);
console.log("push_candidates: daily_drop not repeated once logged today - OK");

// Streak: A already played today (seeded), so streak_risk must not fire for A.
const streakA = await db.query(
  `select user_id from public.push_candidates('${today}T20:00:00Z') where user_id = '${A}' and kind = 'streak_risk'`,
);
if (streakA.rows.length !== 0) throw new Error(`push_candidates: A played today and must not get streak_risk, got ${JSON.stringify(streakA.rows)}`);
console.log("push_candidates: streak_risk withheld from A (already played today) - OK");

const E = "55555555-5555-5555-5555-555555555555";
await db.exec(`
  insert into auth.users values ('${E}');
  insert into public.users (id, phone_hmac, display_name) values ('${E}', 'he', 'Ellis');
  insert into public.devices (user_id, apns_token, env) values ('${E}', 'tokE', 'sandbox');
  insert into public.results (user_id, puzzle_date, attempts, tries, solved, elapsed_ms, score, tz) values
    ('${E}', '${twoAgo}', '[]', 1, true, 10000, 900, 'UTC'),
    ('${E}', '${yest}',   '[]', 1, true, 10000, 900, 'UTC');
`);
const streakE = await db.query(
  `select user_id, kind, payload from public.push_candidates('${today}T20:00:00Z') where user_id = '${E}'`,
);
if (streakE.rows.length !== 1 || streakE.rows[0].kind !== "streak_risk" || streakE.rows[0].payload.streak !== 2) {
  throw new Error(`push_candidates: expected exactly one streak_risk row for E with streak 2, got ${JSON.stringify(streakE.rows)}`);
}
console.log("push_candidates: E (2-day streak, unplayed today) gets streak_risk with streak=2 - OK");

// Passed: at (local) 13:00, B trails mutual friend A; A (top) gets nothing.
const passedB = await db.query(
  `select payload from public.push_candidates('${today}T13:00:00Z') where user_id = '${B}' and kind = 'passed'`,
);
if (passedB.rows.length !== 1 || passedB.rows[0].payload.by !== "Alex" || passedB.rows[0].payload.rank !== 2) {
  throw new Error(`push_candidates: expected a passed row for B (by Alex, rank 2), got ${JSON.stringify(passedB.rows)}`);
}
const passedA = await db.query(
  `select 1 from public.push_candidates('${today}T13:00:00Z') where user_id = '${A}' and kind = 'passed'`,
);
if (passedA.rows.length !== 0) throw new Error("push_candidates: A is top scorer and must not get a passed row");
console.log("push_candidates: passed fires for B (trailing Alex, rank 2) and not for top-scorer A - OK");

// Cap: two notifications already logged today for E caps them out entirely.
await db.exec(`
  insert into public.notification_log (user_id, kind) values ('${E}', 'daily_drop'), ('${E}', 'passed');
`);
const capE = await db.query(`select kind from public.push_candidates('${today}T20:00:00Z') where user_id = '${E}'`);
if (capE.rows.length !== 0) throw new Error(`push_candidates: E hit the daily cap and should get 0 rows, got ${JSON.stringify(capE.rows)}`);
console.log("push_candidates: per-day cap (2) excludes E entirely - OK");

// Preference: disabling push_passed removes B's passed row.
await db.exec(`update public.users set push_passed = false where id = '${B}'`);
const passedBOff = await db.query(
  `select 1 from public.push_candidates('${today}T13:00:00Z') where user_id = '${B}' and kind = 'passed'`,
);
if (passedBOff.rows.length !== 0) throw new Error("push_candidates: B disabled push_passed and should get no passed row");
console.log("push_candidates: push_passed=false suppresses B's passed row - OK");

// Inactivity: clear E's log, then push last_open_at out past the 14-day cutoff.
await db.exec(`delete from public.notification_log where user_id = '${E}'`);
await db.exec(`update public.users set last_open_at = now() - interval '20 days' where id = '${E}'`);
const inactiveE = await db.query(`select kind from public.push_candidates('${today}T20:00:00Z') where user_id = '${E}'`);
if (inactiveE.rows.length !== 0) throw new Error(`push_candidates: E has been inactive 20 days and should get 0 rows, got ${JSON.stringify(inactiveE.rows)}`);
console.log("push_candidates: inactivity (>14 days since last_open_at) excludes E - OK");

// Priority: E eligible for both streak_risk (fixed 20:00) and daily_drop
// (push_daily_at set to 20:00 too) at the same window; streak wins.
await db.exec(`
  update public.users set push_daily_at = '20:00', last_open_at = now() where id = '${E}';
  delete from public.notification_log where user_id = '${E}';
`);
const priorityE = await db.query(`select kind from public.push_candidates('${today}T20:00:00Z') where user_id = '${E}'`);
if (priorityE.rows.length !== 1 || priorityE.rows[0].kind !== "streak_risk") {
  throw new Error(`push_candidates: expected exactly one row for E (streak_risk beats daily_drop), got ${JSON.stringify(priorityE.rows)}`);
}
console.log("push_candidates: streak_risk takes priority over daily_drop for the same user/window - OK");

// ---------------------------------------------------------------------------
// push_candidates: window anchoring (B3) and the sent_today lookback bound (A1)
// ---------------------------------------------------------------------------
// F: midnight wrap. push_daily_at = 00:00, tz UTC. The window containing
// `at` is anchored to the :00/:15/:30/:45 boundary, so 23:45Z's window is
// [23:45, 00:00) — 00:00 is NOT inside it — while the very next window,
// [00:00, 00:15) the following day, does contain it.
const F = "66666666-6666-6666-6666-666666666666";
await db.exec(`
  insert into auth.users values ('${F}');
  insert into public.users (id, phone_hmac, display_name, tz, push_daily_at) values
    ('${F}', 'hf', 'Fin', 'UTC', '00:00');
  insert into public.devices (user_id, apns_token, env) values ('${F}', 'tokF', 'sandbox');
`);
const wrapBefore = await db.query(`select 1 from public.push_candidates('${today}T23:45:00Z') where user_id = '${F}'`);
if (wrapBefore.rows.length !== 0) throw new Error(`push_candidates: F should get no row for the [23:45,00:00) window, got ${JSON.stringify(wrapBefore.rows)}`);
const wrapAfter = await db.query(`select kind from public.push_candidates('${tomorrow}T00:00:00Z') where user_id = '${F}'`);
if (wrapAfter.rows.length !== 1 || wrapAfter.rows[0].kind !== "daily_drop") {
  throw new Error(`push_candidates: F should get daily_drop for the [00:00,00:15) window, got ${JSON.stringify(wrapAfter.rows)}`);
}
console.log("push_candidates: midnight wrap — [23:45,00:00) misses, [00:00,00:15) matches - OK");

// G: non-UTC user. tz America/New_York, push_daily_at 08:00. In September
// New York is on EDT (UTC-4), so 12:00Z is 08:00 local; 08:00Z is 04:00 local.
const G = "77777777-7777-7777-7777-777777777777";
await db.exec(`
  insert into auth.users values ('${G}');
  insert into public.users (id, phone_hmac, display_name, tz, push_daily_at) values
    ('${G}', 'hg', 'Georgia', 'America/New_York', '08:00');
  insert into public.devices (user_id, apns_token, env) values ('${G}', 'tokG', 'sandbox');
`);
const nyMatch = await db.query(`select kind from public.push_candidates('${today}T12:00:00Z') where user_id = '${G}'`);
if (nyMatch.rows.length !== 1 || nyMatch.rows[0].kind !== "daily_drop") {
  throw new Error(`push_candidates: G (America/New_York) should get daily_drop at 12:00Z (08:00 EDT), got ${JSON.stringify(nyMatch.rows)}`);
}
const nyMiss = await db.query(`select 1 from public.push_candidates('${today}T08:00:00Z') where user_id = '${G}'`);
if (nyMiss.rows.length !== 0) throw new Error(`push_candidates: G should get no row at 08:00Z (04:00 EDT), got ${JSON.stringify(nyMiss.rows)}`);
console.log("push_candidates: non-UTC user (America/New_York) fires by local time, not UTC clock time - OK");

// H: window-boundary user. push_daily_at 08:15, tz UTC. Calling exactly at
// 08:00Z (window [08:00,08:15)) must not match (08:15 is the window's
// exclusive end); calling at 08:15Z (window [08:15,08:30)) must.
const H = "88888888-8888-8888-8888-888888888888";
await db.exec(`
  insert into auth.users values ('${H}');
  insert into public.users (id, phone_hmac, display_name, tz, push_daily_at) values
    ('${H}', 'hh', 'Harper', 'UTC', '08:15');
  insert into public.devices (user_id, apns_token, env) values ('${H}', 'tokH', 'sandbox');
`);
const boundaryEarly = await db.query(`select 1 from public.push_candidates('${today}T08:00:00Z') where user_id = '${H}'`);
if (boundaryEarly.rows.length !== 0) throw new Error(`push_candidates: H should get no row at 08:00Z, got ${JSON.stringify(boundaryEarly.rows)}`);
const boundaryOn = await db.query(`select kind from public.push_candidates('${today}T08:15:00Z') where user_id = '${H}'`);
if (boundaryOn.rows.length !== 1 || boundaryOn.rows[0].kind !== "daily_drop") {
  throw new Error(`push_candidates: H should get exactly one daily_drop row at 08:15Z, got ${JSON.stringify(boundaryOn.rows)}`);
}
console.log("push_candidates: window boundary — exactly one of 08:00Z/08:15Z fires (the second) - OK");

// I: sent_today boundary. A notification_log row at yesterday 23:30Z for a
// UTC user must not count toward today's per-day cap or "already sent today".
const I = "99999999-9999-9999-9999-999999999999";
await db.exec(`
  insert into auth.users values ('${I}');
  insert into public.users (id, phone_hmac, display_name, tz, push_daily_at) values
    ('${I}', 'hi', 'Ivy', 'UTC', '09:00');
  insert into public.devices (user_id, apns_token, env) values ('${I}', 'tokI', 'sandbox');
  insert into public.notification_log (user_id, kind, sent_at) values ('${I}', 'daily_drop', '${yest}T23:30:00Z');
`);
const sentTodayBoundary = await db.query(`select kind from public.push_candidates('${today}T09:00:00Z') where user_id = '${I}'`);
if (sentTodayBoundary.rows.length !== 1 || sentTodayBoundary.rows[0].kind !== "daily_drop") {
  throw new Error(`push_candidates: I's yesterday-23:30Z log row should not block today's daily_drop, got ${JSON.stringify(sentTodayBoundary.rows)}`);
}
console.log("push_candidates: a notification_log row from yesterday 23:30Z does not count toward today's cap - OK");

// ---------------------------------------------------------------------------
// delete_account
// ---------------------------------------------------------------------------
// Reuses circle ABC123 (owner A; C joined earlier via join_circle, B later),
// established in the RLS section above.
const preOwner = await db.query(`select owner_id from public.circles where code = 'ABC123'`);
if (preOwner.rows[0].owner_id !== A) throw new Error("delete_account setup: expected A to still own ABC123 before delete_account");

await db.query(`select public.delete_account('${A}')`);
const heirOwner = await db.query(`select owner_id from public.circles where code = 'ABC123'`);
if (heirOwner.rows.length !== 1 || heirOwner.rows[0].owner_id !== C) {
  throw new Error(`delete_account: expected ownership to pass to C (earliest other joiner), got ${JSON.stringify(heirOwner.rows)}`);
}
console.log("delete_account: ownership of ABC123 passed from A to C (earliest other member) - OK");

// Idempotent: A owns nothing now (and A itself is already gone), so calling
// again must be a harmless no-op.
await db.query(`select public.delete_account('${A}')`);
const heirOwnerAgain = await db.query(`select owner_id from public.circles where code = 'ABC123'`);
if (heirOwnerAgain.rows[0].owner_id !== C) throw new Error("delete_account: calling delete_account(A) twice should be a no-op");
console.log("delete_account: calling delete_account(A) again is a harmless no-op - OK");

// D owns a circle with no other members: delete_account(D) must delete it outright.
await db.exec(`insert into public.circles (code, name, owner_id) values ('DSOLO1', 'Dana Solo', '${D}')`);
await db.query(`select public.delete_account('${D}')`);
const dCircle = await db.query(`select 1 from public.circles where code = 'DSOLO1'`);
if (dCircle.rows.length !== 0) throw new Error("delete_account: D's empty owned circle should have been deleted");
console.log("delete_account: D's ownerless (no other members) circle was deleted - OK");

// delete_account now does the full deletion in SQL: auth.users and (via the
// on-delete-cascade FK) public.users must both be gone for D.
const dAuthUsers = await db.query(`select count(*)::int as n from auth.users where id = '${D}'`);
if (dAuthUsers.rows[0].n !== 0) throw new Error(`delete_account: expected auth.users to have 0 rows for D, got ${dAuthUsers.rows[0].n}`);
const dPublicUsers = await db.query(`select count(*)::int as n from public.users where id = '${D}'`);
if (dPublicUsers.rows[0].n !== 0) throw new Error(`delete_account: expected public.users to have 0 rows for D, got ${dPublicUsers.rows[0].n}`);
console.log("delete_account: D's auth.users and public.users rows are both gone (cascade) - OK");

// Owner's own circle_members row can be missing (e.g. removed by some other
// path) before delete_account runs; the heir hand-off must still work purely
// from `circles.owner_id`, not from the owner having a circle_members row.
const J = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const K = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
await db.exec(`
  insert into auth.users values ('${J}'), ('${K}');
  insert into public.users (id, phone_hmac, display_name) values ('${J}', 'hj', 'Jordan'), ('${K}', 'hk', 'Kai');
  insert into public.circles (code, name, owner_id) values ('JOWNER1', 'J Circle', '${J}');
  insert into public.circle_members (circle_id, user_id) select id, '${K}' from public.circles where code = 'JOWNER1';
  delete from public.circle_members where circle_id = (select id from public.circles where code = 'JOWNER1') and user_id = '${J}';
`);
const jMembersBefore = await db.query(`select user_id from public.circle_members where circle_id = (select id from public.circles where code = 'JOWNER1')`);
if (jMembersBefore.rows.length !== 1 || jMembersBefore.rows[0].user_id !== K) {
  throw new Error(`delete_account setup: expected only K in circle_members for JOWNER1, got ${JSON.stringify(jMembersBefore.rows)}`);
}
await db.query(`select public.delete_account('${J}')`);
const jHeir = await db.query(`select owner_id from public.circles where code = 'JOWNER1'`);
if (jHeir.rows.length !== 1 || jHeir.rows[0].owner_id !== K) {
  throw new Error(`delete_account: expected JOWNER1 to pass to K even though J had no circle_members row, got ${JSON.stringify(jHeir.rows)}`);
}
console.log("delete_account: heir hand-off works when the owner's own circle_members row is already absent - OK");

// ---------------------------------------------------------------------------
// is_admin() and the admin review-queue policies on puzzles / lists / list_items
// ---------------------------------------------------------------------------
const admin30 = new Date(Date.now() - 30 * 86400e3).toISOString().slice(0, 10);

await db.exec(`set role app; set app.uid = '${B}';`);
const isAdminBefore = await db.query(`select public.is_admin() as v`);
if (isAdminBefore.rows[0].v !== false) throw new Error("is_admin: B should not be admin yet");

// Non-admin sees only approved puzzles within the +/-14h window (same as the
// puzzles_select policy exercised earlier for start_puzzle).
const winNow = await db.query(`
  select ((now() - interval '14 hours') at time zone 'UTC')::date::text as lo,
         ((now() + interval '14 hours') at time zone 'UTC')::date::text as hi`);
const inWindowSeeded = [twoAgo, yest, today].filter((d) => d >= winNow.rows[0].lo && d <= winNow.rows[0].hi);
const nonAdminCount = await db.query(`select count(*)::int as n from public.puzzles`);
if (nonAdminCount.rows[0].n !== inWindowSeeded.length) {
  throw new Error(`is_admin policies: non-admin B expected to see ${inWindowSeeded.length} puzzles, got ${nonAdminCount.rows[0].n}`);
}
await db.exec(`reset role`);
console.log(`is_admin: B (non-admin) sees only the ${inWindowSeeded.length} in-window approved puzzle(s) - OK`);

// Grant B admin, and add a puzzle well outside the client window (and a
// second, separate list/items so the list_items admin-visibility check below
// isn't confounded by items every user has already played).
await db.exec(`
  insert into public.admins (user_id) values ('${B}');
  insert into public.lists (prompt_template, unit, direction) values ('Order by depth', 'm', 'Deepest first');
  insert into public.list_items (list_id, label, value, source_url, familiarity) values
    (2, 'Mariana Trench', 10935, 'u', 2),
    (2, 'Challenger Deep', 10902, 'u', 3),
    (2, 'Puerto Rico Trench', 8376, 'u', 2),
    (2, 'Sunda Trench', 7290, 'u', 1),
    (2, 'Kermadec Trench', 10047, 'u', 1);
  insert into public.puzzles (date, number, list_id, item_ids, correct_order, status, difficulty) values
    ('${admin30}', 200, 2, '{6,7,8,9,10}', '{6,7,8,9,10}', 'pending', 'easy');
`);

// Compare against the superuser's view so the count does not depend on the time of day.
const allPuzzles = (await db.query(`select count(*)::int as n from public.puzzles`)).rows[0].n;
await db.exec(`set role app; set app.uid = '${B}';`);
const isAdminAfter = await db.query(`select public.is_admin() as v`);
if (isAdminAfter.rows[0].v !== true) throw new Error("is_admin: B should be admin after being added to admins");

const adminCount = await db.query(`select count(*)::int as n from public.puzzles`);
if (adminCount.rows[0].n !== allPuzzles) throw new Error(`is_admin policies: admin B expected to see all ${allPuzzles} puzzles, got ${adminCount.rows[0].n}`);
console.log(`is_admin: B (admin) sees all ${allPuzzles} puzzles, including the out-of-window pending one - OK`);

const approveResult = await db.query(`update public.puzzles set status = 'approved' where date = '${admin30}'`);
const approveCount = approveResult.affectedRows ?? approveResult.rows.length;
if (approveCount !== 1) throw new Error(`is_admin policies: admin update should affect 1 row, got ${approveCount}`);

const adminItems = await db.query(`select value from public.list_items`);
if (adminItems.rows.length !== 10) throw new Error(`is_admin policies: admin should see all 10 list_items rows, got ${adminItems.rows.length}`);
console.log("is_admin: admin B can approve a pending puzzle and read every list_items row - OK");
await db.exec(`reset role`);

// Same actions as C, who is not an admin: both must be no-ops under RLS.
await db.exec(`set role app; set app.uid = '${C}';`);
const cUpdate = await db.query(`update public.puzzles set status = 'approved' where date = '${admin30}'`);
const cUpdateCount = cUpdate.affectedRows ?? cUpdate.rows.length;
if (cUpdateCount !== 0) throw new Error(`is_admin policies: non-admin C's update should affect 0 rows, got ${cUpdateCount}`);
const cItems = await db.query(`select value from public.list_items where list_id = 2`);
if (cItems.rows.length !== 0) throw new Error(`is_admin policies: non-admin C should see 0 list_items for a list they haven't played, got ${cItems.rows.length}`);
await db.exec(`reset role`);
console.log("is_admin: non-admin C's update affects 0 rows and sees 0 unplayed list_items - OK");

// ---------------------------------------------------------------------------
// users.push_* columns
// ---------------------------------------------------------------------------
await db.exec(`set role app; set app.uid = '${B}';`);
await db.query(`update public.users set push_daily_at = '09:30', push_streak = false where id = '${B}'`);
const pushCols = await db.query(`select push_daily_at, push_streak from public.users where id = '${B}'`);
if (pushCols.rows[0].push_streak !== false) throw new Error(`push_* columns: push_streak update should have taken effect, got ${JSON.stringify(pushCols.rows[0])}`);
if (!String(pushCols.rows[0].push_daily_at).startsWith("09:30")) throw new Error(`push_* columns: push_daily_at update should have taken effect, got ${JSON.stringify(pushCols.rows[0])}`);
await db.exec(`reset role`);
console.log("users.push_* columns: app role can update push_daily_at/push_streak for self - OK");

// ---------------------------------------------------------------------------
// puzzles.seed round-trip (B1: seed is now bigint, beyond int32 range)
// ---------------------------------------------------------------------------
await db.exec(`
  insert into public.puzzles (date, number, list_id, item_ids, correct_order, status, difficulty, seed) values
    ('2099-01-01', 99999, 1, '{1,2,3,4,5}', '{1,2,3,4,5}', 'pending', 'easy', 3298495047);
`);
const seedRow = await db.query(`select seed from public.puzzles where date = '2099-01-01'`);
if (String(seedRow.rows[0].seed) !== "3298495047") {
  throw new Error(`puzzles.seed: expected 3298495047 to round-trip, got ${JSON.stringify(seedRow.rows[0])}`);
}
console.log("puzzles.seed: a value beyond int32 range (3298495047) round-trips through the bigint column - OK");

await db.exec(`reset role`);

// ---------------------------------------------------------------------------
// migrations/0003_seed_content.sql: the content-pipeline lists (source-checked, but not yet
// enabled) load cleanly and idempotently, and every list has enough
// candidate values for generate-puzzles' gapsOk (ratio-or-span) rule to have
// a real shot at finding a valid 5-item combination.
//
// Run against a FRESH database rather than `db`: the fixtures inserted above
// reuse ids 1/2 and placeholder source_urls ('u') that would otherwise
// collide with and pollute these checks (on conflict do nothing would skip
// real content rows, and the 'u' placeholders would fail the source_url
// check even though they have nothing to do with the seed file).
// ---------------------------------------------------------------------------
const contentDb = new PGlite({ extensions: { pgcrypto } });
await contentDb.exec(`
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('app.uid', true), '')::uuid $$;
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin;
`);
await contentDb.exec(sql);

const contentSql = fs.readFileSync(new URL("../migrations/0003_seed_content.sql", import.meta.url), "utf8");
await contentDb.exec(contentSql);
await contentDb.exec(contentSql); // re-applying must be a no-op (on conflict do nothing)
console.log("migrations/0003_seed_content.sql: applied twice (idempotent) - OK");

const seedListsCount = await contentDb.query(`select count(*)::int as n from public.lists`);
if (seedListsCount.rows[0].n !== 12) {
  throw new Error(`migrations/0003_seed_content.sql: expected 12 lists, got ${seedListsCount.rows[0].n}`);
}

const seedListRows = await contentDb.query(`select id from public.lists order by id`);
for (const { id } of seedListRows.rows) {
  const itemCount = await contentDb.query(`select count(*)::int as n from public.list_items where list_id = ${id}`);
  if (itemCount.rows[0].n < 18) {
    throw new Error(`migrations/0003_seed_content.sql: list ${id} has only ${itemCount.rows[0].n} items, expected >= 18`);
  }
}

const seedEnabledCount = await contentDb.query(`select count(*)::int as n from public.lists where enabled = true`);
if (seedEnabledCount.rows[0].n !== 0) {
  throw new Error(`migrations/0003_seed_content.sql: expected every seeded list to be enabled=false, found ${seedEnabledCount.rows[0].n} enabled`);
}

const seedBadUrls = await contentDb.query(
  `select count(*)::int as n from public.list_items where source_url not like 'https://en.wikipedia.org/wiki/%'`,
);
if (seedBadUrls.rows[0].n !== 0) {
  throw new Error(`migrations/0003_seed_content.sql: ${seedBadUrls.rows[0].n} list_items rows have a source_url outside https://en.wikipedia.org/wiki/`);
}
console.log("migrations/0003_seed_content.sql: 12 lists, each with >= 18 items, all enabled=false, all source_urls on Wikipedia - OK");

// gapsOk proxy: greedily walk each list's values in sorted order, keeping a
// value when its gap from the last kept value clears the ratio rule OR the
// span rule — mirroring generate-puzzles/handler.ts's gapsOk(values, listSpan).
// Keeping >= 5 values means the generator has a real shot at finding a valid
// 5-item combination for that list.
const SEED_MIN_ADJACENT_GAP = 0.08;
for (const { id } of seedListRows.rows) {
  const valueRows = await contentDb.query(
    `select value::float8 as value from public.list_items where list_id = ${id} order by value asc`,
  );
  const values = valueRows.rows.map((r) => r.value);
  const span = Math.max(...values) - Math.min(...values);

  let lastKept = values[0];
  let kept = 1;
  for (let i = 1; i < values.length; i++) {
    const v = values[i];
    const diff = v - lastKept;
    const ratioOk = diff >= SEED_MIN_ADJACENT_GAP * Math.max(Math.abs(v), Math.abs(lastKept));
    const spanOk = span > 0 && diff >= SEED_MIN_ADJACENT_GAP * span;
    if (ratioOk || spanOk) {
      kept++;
      lastKept = v;
    }
  }
  console.log(`migrations/0003_seed_content.sql: gapsOk proxy kept ${kept} of ${values.length} values for list ${id}`);
  if (kept < 5) {
    throw new Error(`migrations/0003_seed_content.sql: list ${id} only kept ${kept} values under the gapsOk greedy proxy, expected >= 5`);
  }
}
console.log("migrations/0003_seed_content.sql: every list keeps >= 5 values under the gapsOk greedy proxy - OK");

console.log("\nALL SCHEMA CHECKS PASSED");
