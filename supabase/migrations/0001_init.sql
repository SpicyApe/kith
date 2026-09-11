-- 0001_init.sql — Kith v1 schema. See docs/04-technical-architecture.md §2–3.
--
-- Conventions
--   * All tables in `public`, RLS enabled on every one that a client can reach.
--   * `auth.uid()` is the caller. Service role (edge functions) bypasses RLS.
--   * Contact matching tables are NEVER readable by clients; only the
--     `match-contacts` edge function (service role) touches them.
--   * Time: `timestamptz` everywhere; local-date logic uses `users.tz`.

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Users and devices
-- ---------------------------------------------------------------------------

-- Defined here, ahead of `users`, because the tz check constraint below needs
-- it to already exist — a CHECK constraint's function reference is resolved
-- at CREATE TABLE time.
create function public.valid_tz(t text) returns boolean
language sql stable as $$ select exists (select 1 from pg_timezone_names where name = t) $$;

create table public.users (
  id            uuid primary key references auth.users(id) on delete cascade,
  phone_hmac    text not null unique,            -- HMAC(pepper, sha256(E.164)); set by edge fn on signup
  display_name  text not null check (char_length(display_name) between 1 and 30),
  tz            text not null default 'UTC'      -- IANA name, refreshed on every open
                  constraint users_tz_chk check (public.valid_tz(tz)),
  discoverable  boolean not null default true,   -- "Let contacts find me"
  -- 10 hex chars; the signup edge function must still retry on SQLSTATE 23505
  -- (users_invite_code_key) on collision.
  invite_code   text not null unique default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 10)),
  created_at    timestamptz not null default now(),
  last_open_at  timestamptz not null default now()
);

create table public.devices (
  user_id     uuid not null references public.users(id) on delete cascade,
  apns_token  text not null,
  env         text not null check (env in ('sandbox', 'production')),
  updated_at  timestamptz not null default now(),
  primary key (user_id, apns_token)
);

-- ---------------------------------------------------------------------------
-- Contact graph (service role only)
-- ---------------------------------------------------------------------------

-- Peppered HMACs of the owner's contacts. No names, no raw numbers, no plain sha256.
create table public.contact_hashes (
  owner_id      uuid not null references public.users(id) on delete cascade,
  contact_hmac  text not null,
  updated_at    timestamptz not null default now(),
  primary key (owner_id, contact_hmac)
);
create index contact_hashes_hmac_idx on public.contact_hashes (contact_hmac);

-- Materialized friend edges. Row exists when at least one side has the other;
-- `mutual` is the only state the app ever shows.
create table public.matches (
  user_a      uuid not null references public.users(id) on delete cascade,
  user_b      uuid not null references public.users(id) on delete cascade,
  mutual      boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index matches_b_idx on public.matches (user_b) where mutual;

-- One row per contact sync request; `match-contacts` enforces the per-day hash
-- budget and the one-full-sync-per-hour rule from it. Service role only.
create table public.contact_sync_log (
  user_id  uuid not null references public.users(id) on delete cascade,
  at       timestamptz not null default now(),
  hashes   int not null check (hashes >= 0),
  is_full  boolean not null default false
);
create index contact_sync_log_user_at_idx on public.contact_sync_log (user_id, at desc);

-- ---------------------------------------------------------------------------
-- Circles
-- ---------------------------------------------------------------------------

create table public.circles (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique                -- unique join code; shown as KITH-<code>
                default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 10))
                constraint circles_code_fmt check (code ~ '^[A-Z0-9]{6,12}$'),
  name        text not null check (char_length(name) between 1 and 24),
  owner_id    uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.circle_members (
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references public.users(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (circle_id, user_id)
);
create index circle_members_user_idx on public.circle_members (user_id);

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

create table public.lists (
  id               serial primary key,
  prompt_template  text not null,               -- "Order these by the year they were invented"
  unit             text not null,               -- "year", "m", "km", "min"
  direction        text not null,               -- "Earliest at the top"
  ascending        boolean not null default true,
  enabled          boolean not null default true
);

create table public.list_items (
  id           serial primary key,
  list_id      int not null references public.lists(id) on delete cascade,
  label        text not null check (char_length(label) between 1 and 40),
  value        numeric not null,
  source_url   text not null,
  familiarity  smallint not null check (familiarity between 1 and 3),
  fact         text,                            -- one-line reveal fact
  unique (list_id, label)
);

create table public.puzzles (
  date           date primary key,
  number         int not null unique,
  list_id        int not null references public.lists(id),
  item_ids       int[] not null check (cardinality(item_ids) = 5),
  correct_order  int[] not null check (cardinality(correct_order) = 5),
  status         text not null default 'pending' check (status in ('pending', 'approved')),
  difficulty     text not null check (difficulty in ('easy', 'medium', 'hard')),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------------

create table public.results (
  user_id       uuid not null references public.users(id) on delete cascade,
  puzzle_date   date not null references public.puzzles(date),
  attempts      jsonb not null,                 -- [{order:[..], feedback:[..], elapsedMs:n}]
  tries         smallint not null check (tries between 1 and 3),
  solved        boolean not null,
  elapsed_ms    int not null check (elapsed_ms >= 0),
  score         int not null check (score between 0 and 1000),
  tz            text not null,
  elapsed_source text not null default 'client' check (elapsed_source in ('server', 'client')),
  submitted_at  timestamptz not null default now(),
  primary key (user_id, puzzle_date)
);
create index results_date_score_idx on public.results (puzzle_date, score desc, elapsed_ms asc);

-- First reveal of a puzzle per user, recorded by `start_puzzle`. `submit-result`
-- uses it to clamp the client's elapsed time. No client policies: only the RPC
-- (security definer) writes it and only the service role reads it.
create table public.puzzle_starts (
  user_id      uuid not null references public.users(id) on delete cascade,
  puzzle_date  date not null references public.puzzles(date),
  started_at   timestamptz not null default now(),
  primary key (user_id, puzzle_date)
);

create table public.reactions (
  from_user    uuid not null references public.users(id) on delete cascade,
  to_user      uuid not null references public.users(id) on delete cascade,
  puzzle_date  date not null,
  emoji        text not null check (emoji in ('🔥','👏','😂','😭','🫡','🙄')),
  created_at   timestamptz not null default now(),
  primary key (from_user, to_user, puzzle_date),
  check (from_user <> to_user)
);
-- Covers the board/reactions-strip fetch (to_user, puzzle_date).
create index reactions_to_date_idx on public.reactions (to_user, puzzle_date);

create table public.taunts (
  user_id      uuid not null references public.users(id) on delete cascade,
  puzzle_date  date not null,
  text         text not null check (char_length(text) between 1 and 80),
  hidden_by    uuid[] not null default '{}',
  created_at   timestamptz not null default now(),
  primary key (user_id, puzzle_date)
);

create table public.notification_log (
  user_id  uuid not null references public.users(id) on delete cascade,
  kind     text not null check (kind in ('daily_drop', 'streak_risk', 'passed')),
  sent_at  timestamptz not null default now()
);
create index notification_log_user_day_idx on public.notification_log (user_id, sent_at desc);

create table public.events (
  id       bigserial primary key,
  user_id  uuid references public.users(id) on delete set null,
  name     text not null                        -- bounded name space
             constraint events_name_chk check (name in (
               'onboard_step','contacts_granted','contacts_limited','puzzle_start','puzzle_submit',
               'share_tap','share_complete','match_found','circle_create','circle_join','push_open',
               'board_view','react','taunt','delete_account','circle_join_attempt')),
  props    jsonb not null default '{}'          -- bounded payload size
             constraint events_props_size_chk check (pg_column_size(props) < 2048),
  at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Two users can see each other's play if they are mutual contacts or share a circle.
create function public.can_see(viewer uuid, target uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select viewer = target
      or exists (
        select 1 from matches m
        where m.mutual
          and m.user_a = least(viewer, target)
          and m.user_b = greatest(viewer, target))
      or exists (
        select 1 from circle_members a
        join circle_members b on a.circle_id = b.circle_id
        where a.user_id = viewer and b.user_id = target);
$$;

-- Caller-bound wrapper: the 2-arg form takes arbitrary uuids and must never be
-- directly executable, or anyone can walk the whole contacts graph.
create function public.can_see(target uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.can_see(auth.uid(), target);
$$;

-- Current streak: consecutive dates ending today-or-yesterday in the user's tz.
create function public.streak(u uuid)
returns int language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  today date;
  d date;
  n int := 0;
begin
  select (now() at time zone coalesce(
            (select z.name from users x join pg_timezone_names z on z.name = x.tz where x.id = u),
            'UTC'))::date
    into today;
  if today is null then return 0; end if;
  if exists (select 1 from results where user_id = u and puzzle_date = today) then
    d := today;
  elsif exists (select 1 from results where user_id = u and puzzle_date = today - 1) then
    d := today - 1;
  else
    return 0;
  end if;
  loop
    exit when not exists (select 1 from results where user_id = u and puzzle_date = d);
    n := n + 1;
    d := d - 1;
  end loop;
  return n;
end;
$$;

-- Caller-bound wrapper for streak(); the arbitrary-uuid form must not be directly executable.
create function public.my_streak()
returns int language sql stable security definer set search_path = public, pg_temp as $$
  select public.streak(auth.uid());
$$;

-- Friend ids for a user (mutual only).
create function public.friend_ids(u uuid)
returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  select case when user_a = u then user_b else user_a end
  from matches where mutual and (user_a = u or user_b = u);
$$;

-- Breaks the infinite recursion in circle_members_select (a policy on
-- circle_members that queried circle_members from inside itself, 42P17).
-- Rebuilds every `matches` row involving `owner` from `contact_hashes`.
-- Called by `match-contacts` (service role) after each sync and by the
-- `users_discoverable_changed` trigger. Never callable by clients.
--   have_them   = users whose phone_hmac is in owner's contact list (and who are discoverable)
--   they_have_me = users whose contact list contains owner's phone_hmac (only if owner is discoverable)
--   mutual = in both. Rows involving owner that are in neither set are deleted.
create function public.recompute_matches(owner uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  my_hmac text;
  me_discoverable boolean;
begin
  select phone_hmac, discoverable into my_hmac, me_discoverable from users where id = owner;
  if my_hmac is null then return; end if;

  create temp table _edges on commit drop as
  with have_them as (
    select u.id from contact_hashes ch
    join users u on u.phone_hmac = ch.contact_hmac
    where ch.owner_id = owner and u.discoverable and u.id <> owner
  ),
  they_have_me as (
    select ch.owner_id as id from contact_hashes ch
    where ch.contact_hmac = my_hmac and me_discoverable and ch.owner_id <> owner
  )
  select coalesce(h.id, t.id) as other,
         (h.id is not null and t.id is not null) as mutual
  from have_them h full outer join they_have_me t on t.id = h.id;

  delete from matches m
  where (m.user_a = owner or m.user_b = owner)
    and not exists (select 1 from _edges e
                    where e.other = case when m.user_a = owner then m.user_b else m.user_a end);

  insert into matches (user_a, user_b, mutual, updated_at)
  select least(owner, e.other), greatest(owner, e.other), e.mutual, now() from _edges e
  on conflict (user_a, user_b) do update
    set mutual = excluded.mutual, updated_at = now()
    where matches.mutual is distinct from excluded.mutual;

  drop table _edges;
end;
$$;

-- Aggregates the caller's sync-log rows since `since` in SQL instead of pulling
-- every row into the edge function and summing in JS. Used by match-contacts to
-- enforce the per-hour request/full-sync caps and the daily hash cap. Service
-- role only.
create function public.sync_usage(u uuid, since timestamptz)
returns table (full_syncs int, hashes int, requests int)
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(count(*) filter (where is_full), 0)::int,
         coalesce(sum(hashes), 0)::int,
         count(*)::int
  from contact_sync_log where user_id = u and at >= since;
$$;

create function public.is_circle_member(c uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from circle_members where circle_id = c and user_id = auth.uid());
$$;

-- Leaderboard. kind: 'friends' | 'circle' | 'everyone'. period: 'today' | 'week' | 'all'.
-- Returns rows for the scope's members with today's (or summed) score, plus the
-- rank they held on the previous period over the same member set. Top 100 (or
-- 1000) rows, plus the caller's own row and rank when they fall outside that cut.
create function public.board(kind text, scope_id uuid, period text, for_date date)
returns table (
  user_id uuid, display_name text, score int, tries smallint, elapsed_ms int,
  attempts jsonb, played boolean, rank int, prev_rank int
) language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid();
  d_from date; d_to date; p_from date; p_to date;
begin
  if kind = 'everyone' and period <> 'today' then
    raise exception 'everyone board is today-only';
  end if;
  case period
    when 'today' then d_from := for_date; d_to := for_date;
                      p_from := for_date - 1; p_to := for_date - 1;
    when 'week'  then d_from := date_trunc('week', for_date)::date; d_to := d_from + 6;
                      p_from := d_from - 7; p_to := d_from - 1;
    when 'all'   then d_from := '2000-01-01'; d_to := for_date;
                      p_from := '2000-01-01'; p_to := for_date - 1;
    else raise exception 'bad period';
  end case;

  return query
  with members as (
    select u.id from users u
    where case kind
      when 'friends'  then u.id = me or u.id in (select friend_ids(me))
      when 'circle'   then u.id in (select cm.user_id from circle_members cm where cm.circle_id = scope_id)
                            and exists (select 1 from circle_members x where x.circle_id = scope_id and x.user_id = me)
      when 'everyone' then true
    end
  ),
  cur as (
    select m.id,
           coalesce(sum(r.score), 0)::int as score,
           bool_or(r.user_id is not null) as played,
           max(r.tries) filter (where period = 'today') as tries,
           max(r.elapsed_ms) filter (where period = 'today') as elapsed_ms,
           (array_agg(r.attempts) filter (where r.attempts is not null and period = 'today'))[1] as attempts,
           min(r.submitted_at) filter (where period = 'today') as submitted_at
    from members m
    left join results r on r.user_id = m.id and r.puzzle_date between d_from and d_to
    group by m.id
  ),
  prev as (
    select m.id, coalesce(sum(r.score), 0)::int as score,
           bool_or(r.user_id is not null) as played,
           max(r.elapsed_ms) filter (where period = 'today') as elapsed_ms
    from members m
    left join results r on r.user_id = m.id and r.puzzle_date between p_from and p_to
    group by m.id
  ),
  ranked as (
    select c.id,
           case when c.played then rank() over (
             order by c.played desc, c.score desc, c.elapsed_ms asc nulls last, c.submitted_at asc nulls last
           ) end as rank
    from cur c
  ),
  prev_ranked as (
    select p.id,
           case when p.played then rank() over (order by p.played desc, p.score desc, p.elapsed_ms asc nulls last) end as rank
    from prev p
  )
  select * from (
    select c.id, u.display_name, c.score, c.tries, c.elapsed_ms,
           case when kind = 'everyone' then null else c.attempts end as attempts,
           c.played, rk.rank::int as rank, pr.rank::int as prev_rank
    from cur c
    join users u on u.id = c.id
    join ranked rk on rk.id = c.id
    left join prev_ranked pr on pr.id = c.id
    order by c.played desc, c.score desc, c.elapsed_ms asc nulls last, c.submitted_at asc nulls last
    limit case when kind = 'everyone' then 100 else 1000 end
  ) top
  union all
  select c.id, u.display_name, c.score, c.tries, c.elapsed_ms, null::jsonb as attempts,
         c.played, rk.rank::int as rank, pr.rank::int as prev_rank
  from cur c
  join users u on u.id = c.id
  join ranked rk on rk.id = c.id
  left join prev_ranked pr on pr.id = c.id
  where kind = 'everyone' and c.id = me and rk.rank > 100;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.users            enable row level security;
alter table public.devices          enable row level security;
alter table public.contact_hashes   enable row level security;   -- no client policies: service role only
alter table public.matches          enable row level security;
alter table public.contact_sync_log enable row level security;   -- no client policies
alter table public.circles          enable row level security;
alter table public.circle_members   enable row level security;
alter table public.lists            enable row level security;
alter table public.list_items       enable row level security;
alter table public.puzzles          enable row level security;
alter table public.results          enable row level security;
alter table public.puzzle_starts    enable row level security;   -- no client policies
alter table public.reactions        enable row level security;
alter table public.taunts           enable row level security;
alter table public.notification_log enable row level security;   -- service role only
alter table public.events           enable row level security;   -- no client policies: track() is the only path

-- users: read self and anyone you can see; update self only (never phone_hmac).
create policy users_select on public.users for select to authenticated
  using (public.can_see(users.id));
create policy users_update on public.users for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- devices: own rows.
create policy devices_all on public.devices for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- matches: readable only where you are a side and it is mutual. Never writable by clients.
create policy matches_select on public.matches for select to authenticated
  using (mutual and auth.uid() in (user_a, user_b));

-- circles: members read; anyone may insert as owner; owner updates/deletes.
create policy circles_select on public.circles for select to authenticated
  using (public.is_circle_member(circles.id));
create policy circles_insert on public.circles for insert to authenticated
  with check (owner_id = auth.uid());
create policy circles_update on public.circles for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy circles_delete on public.circles for delete to authenticated
  using (owner_id = auth.uid());

-- circle_members: members read the roster; join by code happens through the
-- `join-circle` RPC (security definer) so the code is validated; leave = delete own row;
-- owner may remove anyone.
create policy circle_members_select on public.circle_members for select to authenticated
  using (public.is_circle_member(circle_members.circle_id));
create policy circle_members_delete on public.circle_members for delete to authenticated
  using (user_id = auth.uid()
      or exists (select 1 from public.circles c
                 where c.id = circle_members.circle_id and c.owner_id = auth.uid()));

-- content: puzzles readable when approved and within ±14h of UTC now. Values and
-- facts live in list_items, which clients read only for dates they have played.
create policy puzzles_select on public.puzzles for select to authenticated
  using (status = 'approved'
     and date between ((now() - interval '14 hours') at time zone 'UTC')::date
                  and ((now() + interval '14 hours') at time zone 'UTC')::date);
create policy lists_select on public.lists for select to authenticated using (true);
create policy list_items_select on public.list_items for select to authenticated
  using (exists (
    select 1 from public.results r
    join public.puzzles p on p.date = r.puzzle_date
    where r.user_id = auth.uid() and list_items.id = any(p.item_ids)));

-- results: read where you can see the user. Inserts only via `submit-result` (service role).
create policy results_select on public.results for select to authenticated
  using (public.can_see(results.user_id));

-- reactions: insert/delete own, only toward someone you can see who has also
-- played that date; read where you can see both sides.
create policy reactions_select on public.reactions for select to authenticated
  using (public.can_see(reactions.to_user) and public.can_see(reactions.from_user));
create policy reactions_insert on public.reactions for insert to authenticated
  with check (from_user = auth.uid() and public.can_see(reactions.to_user)
              and exists (select 1 from public.results r where r.user_id = auth.uid() and r.puzzle_date = reactions.puzzle_date)
              and exists (select 1 from public.results r2 where r2.user_id = reactions.to_user and r2.puzzle_date = reactions.puzzle_date));
create policy reactions_delete on public.reactions for delete to authenticated
  using (from_user = auth.uid());

-- taunts: write-once own (after playing); visible to people who can see you AND have played that date.
create policy taunts_insert on public.taunts for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.results r where r.user_id = auth.uid() and r.puzzle_date = taunts.puzzle_date));
create policy taunts_select on public.taunts for select to authenticated
  using (user_id = auth.uid()
      or (public.can_see(taunts.user_id)
          and not (auth.uid() = any(hidden_by))
          and exists (select 1 from public.results r where r.user_id = auth.uid() and r.puzzle_date = taunts.puzzle_date)));

-- ---------------------------------------------------------------------------
-- RPCs callable by clients
-- ---------------------------------------------------------------------------

-- join_circle: format-validated code (circles_code_fmt), a per-user join-attempt
-- rate limit, and the 50-member and 10-circle caps (row-locked to serialize
-- concurrent joins to the same circle).
create function public.join_circle(join_code text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare cid uuid;
begin
  if (select count(*) from events
      where user_id = auth.uid() and name = 'circle_join_attempt'
        and at > now() - interval '1 hour') >= 10 then
    raise exception 'too many join attempts' using errcode = 'P0005';
  end if;
  insert into events (user_id, name) values (auth.uid(), 'circle_join_attempt');

  select id into cid from circles where code = replace(upper(trim(join_code)), 'KITH-', '');
  if cid is null then raise exception 'no such circle' using errcode = 'P0002'; end if;
  -- `for update` can't combine with an aggregate (count(*)); lock the parent
  -- circles row instead so concurrent joins to the same circle serialize.
  perform 1 from circles where id = cid for update;
  if (select count(*) from circle_members where circle_id = cid) >= 50 then
    raise exception 'circle is full' using errcode = 'P0003';
  end if;
  if (select count(*) from circle_members where user_id = auth.uid()) >= 10 then
    raise exception 'too many circles' using errcode = 'P0004';
  end if;
  insert into circle_members (circle_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  return cid;
end;
$$;

-- track: rate-limited event logging (60/minute/user, silently dropped past that).
-- Returns the puzzle for `d` in client shape and records the caller's first
-- reveal in `puzzle_starts`. Same date window and approval rule as the puzzles
-- RLS policy, re-checked here because the function is security definer.
-- `items` are in presentation (shuffled) order; `correctOrder` is the answer.
create function public.start_puzzle(d date)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  p puzzles%rowtype;
  l lists%rowtype;
  items jsonb;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if d < ((now() - interval '14 hours') at time zone 'UTC')::date
     or d > ((now() + interval '14 hours') at time zone 'UTC')::date then
    raise exception 'date outside window' using errcode = 'P0006';
  end if;
  select * into p from puzzles where date = d and status = 'approved';
  if p.date is null then raise exception 'no puzzle' using errcode = 'P0002'; end if;
  select * into l from lists where id = p.list_id;
  if l.id is null then raise exception 'bad list' using errcode = 'P0002'; end if;

  -- puzzle_starts FKs users(id); a caller who finished OTP but never called
  -- `register` has no users row yet, so skip the insert rather than 23503.
  if exists (select 1 from users where id = auth.uid()) then
    insert into puzzle_starts (user_id, puzzle_date) values (auth.uid(), d) on conflict do nothing;
  end if;

  select jsonb_agg(jsonb_build_object('id', li.id, 'label', li.label) order by ord.n)
    into items
  from unnest(p.item_ids) with ordinality as ord(id, n)
  join list_items li on li.id = ord.id;
  if items is null or jsonb_array_length(items) <> 5 then
    raise exception 'bad puzzle items' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'date', to_char(p.date, 'YYYY-MM-DD'),
    'number', p.number,
    'prompt', l.prompt_template,
    'direction', l.direction,
    'items', items,
    'correctOrder', to_jsonb(p.correct_order));
end;
$$;

create function public.track(p_name text, p_props jsonb default '{}')
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (select count(*) from events where user_id = auth.uid() and at > now() - interval '1 minute') >= 60 then
    return;
  end if;
  insert into events (user_id, name, props) values (auth.uid(), p_name, coalesce(p_props, '{}'));
end;
$$;

-- Lets a client hide a taunt instead of just not seeing a policy for it.
create function public.hide_taunt(author uuid, d date)
returns void language sql security definer set search_path = public, pg_temp as $$
  update taunts set hidden_by = array_append(hidden_by, auth.uid())
  where user_id = author and puzzle_date = d
    and not (auth.uid() = any(hidden_by))
    and public.can_see(auth.uid(), author);
$$;

-- Owner auto-joins their own circle, subject to the same 10-circle cap as join_circle.
create function public.circle_owner_joins()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (select count(*) from circle_members where user_id = new.owner_id) >= 10 then
    raise exception 'too many circles' using errcode = 'P0004';
  end if;
  insert into circle_members (circle_id, user_id) values (new.id, new.owner_id);
  return new;
end;
$$;
create trigger circles_owner_joins after insert on public.circles
  for each row execute function public.circle_owner_joins();

-- Keeps the graph honest the instant a client flips `discoverable`, instead of
-- leaving stale `mutual = true` rows until some other user's next sync happens
-- to recompute them. Turning discovery off also deletes the owner's uploaded
-- contact hashes (they opted out of being matchable by them too).
create function public.users_discoverable_changed()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.discoverable is distinct from old.discoverable then
    if not new.discoverable then
      delete from contact_hashes where owner_id = new.id;
    end if;
    perform public.recompute_matches(new.id);
  end if;
  return new;
end;
$$;
create trigger users_discoverable_changed after update of discoverable on public.users
  for each row execute function public.users_discoverable_changed();

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- Supabase grants EXECUTE on newly created functions to `anon`/`authenticated`
-- by default, so the arbitrary-uuid / unscoped helpers must be explicitly
-- revoked here and only the caller-bound wrappers and client RPCs re-granted.

revoke all on function public.can_see(uuid, uuid)  from public, anon, authenticated;
revoke all on function public.streak(uuid)          from public, anon, authenticated;
revoke all on function public.friend_ids(uuid)      from public, anon, authenticated;
revoke all on function public.circle_owner_joins()  from public, anon, authenticated;
revoke all on function public.recompute_matches(uuid) from public, anon, authenticated;
revoke all on function public.users_discoverable_changed() from public, anon, authenticated;
revoke all on function public.sync_usage(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.start_puzzle(date)    from public, anon;
grant execute on function public.start_puzzle(date) to authenticated;
-- The revokes above also strip the default PUBLIC EXECUTE grant these functions
-- got on creation, so the edge functions (which call them as service_role) need
-- it re-granted explicitly.
grant execute on function public.recompute_matches(uuid), public.streak(uuid),
                          public.start_puzzle(date) to service_role;
grant execute on function public.sync_usage(uuid, timestamptz) to service_role;
revoke all on function public.board(text, uuid, text, date) from public, anon;
revoke all on function public.join_circle(text)     from public, anon;
revoke all on function public.track(text, jsonb)    from public, anon;
grant execute on function public.can_see(uuid), public.my_streak(),
                          public.is_circle_member(uuid) to authenticated;
-- (the revokes above strip the default PUBLIC grant board/join_circle/track were
-- created with; re-grant explicitly so authenticated clients can still call them)
grant execute on function public.board(text, uuid, text, date),
                          public.join_circle(text),
                          public.track(text, jsonb) to authenticated;
grant execute on function public.hide_taunt(uuid, date) to authenticated;

-- users: never expose or allow rewriting phone_hmac / invite_code from the client.
revoke select, update on public.users from anon, authenticated;
grant select (id, display_name, tz, discoverable, invite_code, created_at, last_open_at)
  on public.users to authenticated;
grant update (display_name, tz, discoverable, last_open_at)
  on public.users to authenticated;

-- circles: the owner may rename but never rewrite the join code, and only
-- (name, owner_id) are settable on insert.
revoke insert, update on public.circles from anon, authenticated;
grant insert (name, owner_id) on public.circles to authenticated;
grant update (name) on public.circles to authenticated;
