-- 0006 — games hub: Stars, Duo, Trail alongside Lineup (docs/07-games-hub.md).
--
--   daily_games   generated grid puzzles, one per (date, game); `solution` never reaches clients
--   game_starts   first reveal per user/date/game (elapsed clamp), service role only
--   game_results  one result per user/date/game, inserted only by `submit-game`
-- `board()` gains a game picker ('lineup' default, 'stars', 'duo', 'trail', 'total');
-- `streak()` counts a day when any game was played; `start_game(d, g)` mirrors start_puzzle.

create table public.daily_games (
  date        date not null,
  game        text not null check (game in ('stars', 'duo', 'trail')),
  number      int not null,
  spec        jsonb not null,
  solution    jsonb not null,
  status      text not null default 'approved' check (status in ('pending', 'approved')),
  difficulty  text not null check (difficulty in ('easy', 'medium', 'hard')),
  seed        bigint not null default 0,
  created_at  timestamptz not null default now(),
  primary key (date, game),
  unique (game, number)
);

create table public.game_starts (
  user_id     uuid not null references public.users(id) on delete cascade,
  date        date not null,
  game        text not null check (game in ('stars', 'duo', 'trail')),
  started_at  timestamptz not null default now(),
  primary key (user_id, date, game)
);

create table public.game_results (
  user_id         uuid not null references public.users(id) on delete cascade,
  date            date not null,
  game            text not null check (game in ('stars', 'duo', 'trail')),
  elapsed_ms      int not null check (elapsed_ms >= 0),
  elapsed_source  text not null default 'client' check (elapsed_source in ('server', 'client')),
  mistakes        int not null default 0 check (mistakes between 0 and 999),
  solved          boolean not null,
  gave_up         boolean not null default false,
  score           int not null check (score between 0 and 1000),
  tz              text not null,
  submitted_at    timestamptz not null default now(),
  primary key (user_id, date, game),
  foreign key (date, game) references public.daily_games(date, game)
);
create index game_results_date_game_score_idx on public.game_results (date, game, score desc, elapsed_ms asc);

-- ---------------------------------------------------------------------------
-- Played-any-game helper and streak
-- ---------------------------------------------------------------------------

create function public.played_on(u uuid, d date)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from results r where r.user_id = u and r.puzzle_date = d)
      or exists (select 1 from game_results g where g.user_id = u and g.date = d);
$$;

create or replace function public.streak(u uuid)
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
  if played_on(u, today) then
    d := today;
  elsif played_on(u, today - 1) then
    d := today - 1;
  else
    return 0;
  end if;
  loop
    exit when not played_on(u, d);
    n := n + 1;
    d := d - 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- push_candidates (0001, patched): "played today" must count grid games too,
-- not just Lineup, now that played_on(u, d) covers both. B1/B-LOW:
--   * streak_risk's "still unplayed today" test now uses played_on(e.id, e.ld)
--     instead of checking `results` alone, so a played grid game correctly
--     suppresses the streak-risk push.
--   * daily_drop's friendsPlayed counts distinct friends across both
--     `results` and `game_results` for the day, not just Lineup.
-- ---------------------------------------------------------------------------

create or replace function public.push_candidates(at timestamptz)
returns table (user_id uuid, kind text, apns_token text, env text, payload jsonb)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  return query
  with w as (
    -- The 15-minute window containing `at`, e.g. 09:07 -> [09:00, 09:15).
    select date_trunc('hour', at) + (floor(extract(minute from at) / 15) * interval '15 minutes') as win_start
  ),
  u as (
    select us.id, us.tz, us.push_daily, us.push_daily_at, us.push_streak, us.push_passed,
           (w.win_start at time zone us.tz) as lt,
           (w.win_start at time zone us.tz)::date as ld,
           ((w.win_start + interval '15 minutes') at time zone us.tz)::time as lt_end
    from users us cross join w
    where us.last_open_at > at - interval '14 days'
      and exists (select 1 from devices d where d.user_id = us.id)
  ),
  sent_today as (
    select nl.user_id, nl.kind, count(*) as n
    from notification_log nl join u on u.id = nl.user_id
    where (nl.sent_at at time zone u.tz)::date = u.ld
      and nl.sent_at > at - interval '2 days'
    group by nl.user_id, nl.kind
  ),
  totals as (select st.user_id, sum(st.n) as n from sent_today st group by st.user_id),
  eligible as (
    select u.* from u
    left join totals t on t.user_id = u.id
    where coalesce(t.n, 0) < 2
  ),
  -- window test: [lt::time, lt_end) with midnight wrap
  daily as (
    select e.id, 'daily_drop'::text as kind,
           jsonb_build_object('friendsPlayed',
             (select count(distinct uid) from (
                select r.user_id as uid from results r where r.puzzle_date = e.ld
                union
                select g.user_id from game_results g where g.date = e.ld
              ) x where uid in (select friend_ids(e.id)))) as payload
    from eligible e
    where e.push_daily
      and (case when e.lt::time <= e.lt_end
                then e.push_daily_at >= e.lt::time and e.push_daily_at < e.lt_end
                else e.push_daily_at >= e.lt::time or e.push_daily_at < e.lt_end end)
      and not exists (select 1 from sent_today s where s.user_id = e.id and s.kind = 'daily_drop')
  ),
  streak_risk as (
    select e.id, 'streak_risk'::text as kind,
           jsonb_build_object('streak', st.s,
                              'hoursLeft', greatest(0, 24 - extract(hour from e.lt))::int) as payload
    from eligible e
    join lateral (select streak(e.id) as s) st on true
    where e.push_streak
      and (case when e.lt::time <= e.lt_end
                then time '20:00' >= e.lt::time and time '20:00' < e.lt_end
                else time '20:00' >= e.lt::time or time '20:00' < e.lt_end end)
      and not played_on(e.id, e.ld)
      and st.s >= 2
      and not exists (select 1 from sent_today s where s.user_id = e.id and s.kind = 'streak_risk')
  ),
  passed as (
    select e.id, 'passed'::text as kind,
           jsonb_build_object('by', p.display_name, 'others', p.others, 'rank', p.rank) as payload
    from eligible e
    join lateral (
      with mine as (select r.score from results r where r.user_id = e.id and r.puzzle_date = e.ld),
           better as (
             select us.display_name, r.score, r.submitted_at
             from results r join users us on us.id = r.user_id
             where r.puzzle_date = e.ld and r.user_id in (select friend_ids(e.id))
               and r.score > (select score from mine))
      select (select display_name from better order by submitted_at desc limit 1) as display_name,
             (select count(*) - 1 from better) as others,
             (select count(*) + 1 from better) as rank
      where exists (select 1 from mine) and exists (select 1 from better)
    ) p on true
    where e.push_passed
      and e.lt::time >= time '12:00'
      and not exists (select 1 from sent_today s where s.user_id = e.id and s.kind = 'passed')
  ),
  chosen as (
    -- one kind per user per run: streak beats passed beats daily
    select distinct on (c.id) c.id, c.kind, c.payload
    from (select * from streak_risk union all select * from passed union all select * from daily) c
    order by c.id, case c.kind when 'streak_risk' then 0 when 'passed' then 1 else 2 end
  )
  select ch.id, ch.kind, d.apns_token, d.env, ch.payload
  from chosen ch join devices d on d.user_id = ch.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Board with a game picker
-- ---------------------------------------------------------------------------

drop function public.board(text, uuid, text, date);

-- game_kind: 'lineup' (default; tries/attempts populated), 'stars' | 'duo' | 'trail'
-- (elapsed only), or 'total' (sum of all four per day; unplayed games count 0).
create function public.board(kind text, scope_id uuid, period text, for_date date, game_kind text default 'lineup')
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
  if game_kind not in ('lineup', 'stars', 'duo', 'trail', 'total') then
    raise exception 'bad game';
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
  scores as (
    select r.user_id, r.puzzle_date as date, r.score, r.elapsed_ms, r.tries, r.attempts, r.submitted_at
    from results r
    where game_kind in ('lineup', 'total') and r.puzzle_date between p_from and d_to
    union all
    select g.user_id, g.date, g.score, g.elapsed_ms, null::smallint, null::jsonb, g.submitted_at
    from game_results g
    where (game_kind = 'total' or g.game = game_kind) and g.date between p_from and d_to
  ),
  cur as (
    select m.id,
           coalesce(sum(s.score), 0)::int as score,
           bool_or(s.user_id is not null) as played,
           max(s.tries) filter (where period = 'today') as tries,
           sum(s.elapsed_ms) filter (where period = 'today')::int as elapsed_ms,
           (array_agg(s.attempts) filter (where s.attempts is not null and period = 'today'))[1] as attempts,
           min(s.submitted_at) filter (where period = 'today') as submitted_at
    from members m
    left join scores s on s.user_id = m.id and s.date between d_from and d_to
    group by m.id
  ),
  prev as (
    select m.id, coalesce(sum(s.score), 0)::int as score,
           bool_or(s.user_id is not null) as played,
           sum(s.elapsed_ms) filter (where period = 'today')::int as elapsed_ms
    from members m
    left join scores s on s.user_id = m.id and s.date between p_from and p_to
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
-- start_game: records the first reveal and returns the spec (never the solution)
-- ---------------------------------------------------------------------------

create function public.start_game(d date, g text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  row_ daily_games%rowtype;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if g not in ('stars', 'duo', 'trail') then raise exception 'bad game' using errcode = '22023'; end if;
  if d < ((now() - interval '14 hours') at time zone 'UTC')::date
     or d > ((now() + interval '14 hours') at time zone 'UTC')::date then
    raise exception 'date outside window' using errcode = 'P0006';
  end if;
  select * into row_ from daily_games where date = d and game = g and status = 'approved';
  if row_.date is null then raise exception 'no puzzle' using errcode = 'P0002'; end if;
  if exists (select 1 from users where id = auth.uid()) then
    insert into game_starts (user_id, date, game) values (auth.uid(), d, g) on conflict do nothing;
  end if;
  return jsonb_build_object(
    'date', to_char(row_.date, 'YYYY-MM-DD'),
    'game', row_.game,
    'number', row_.number,
    'difficulty', row_.difficulty,
    'spec', row_.spec);
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------

alter table public.daily_games  enable row level security;
alter table public.game_starts  enable row level security;   -- no client policies
alter table public.game_results enable row level security;

-- Clients may list today's games (for the hub) but never read `solution`: the row
-- policy limits dates, the column grant limits columns. Admins see every date.
create policy daily_games_select on public.daily_games for select to authenticated
  using (public.is_admin() or (status = 'approved'
     and date between ((now() - interval '14 hours') at time zone 'UTC')::date
                  and ((now() + interval '14 hours') at time zone 'UTC')::date));
revoke select on public.daily_games from anon, authenticated;
grant select (date, game, number, status, difficulty, spec, created_at) on public.daily_games to authenticated;

create policy game_results_select on public.game_results for select to authenticated
  using (public.can_see(game_results.user_id));

revoke all on function public.played_on(uuid, date) from public, anon, authenticated;
revoke all on function public.board(text, uuid, text, date, text) from public, anon;
grant execute on function public.board(text, uuid, text, date, text) to authenticated;
revoke all on function public.start_game(date, text) from public, anon;
grant execute on function public.start_game(date, text) to authenticated;
grant execute on function public.played_on(uuid, date), public.start_game(date, text) to service_role;
