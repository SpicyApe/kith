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

console.log("\nALL SCHEMA CHECKS PASSED");
