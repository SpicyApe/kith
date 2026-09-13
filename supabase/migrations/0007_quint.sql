-- 0007 — Quint: the fifth daily game (docs/07-games-hub.md §"Quint"), a Wordle-style
-- five-letter word guesser alongside Stars/Duo/Trail. Extends the three `game` check
-- constraints from 0006 to include 'quint', and recreates `board()` / `start_game()`
-- with 'quint' in their game lists (bodies otherwise unchanged from 0006).

alter table public.daily_games  drop constraint daily_games_game_check;
alter table public.daily_games  add  constraint daily_games_game_check
  check (game in ('stars', 'duo', 'trail', 'quint'));

alter table public.game_starts  drop constraint game_starts_game_check;
alter table public.game_starts  add  constraint game_starts_game_check
  check (game in ('stars', 'duo', 'trail', 'quint'));

alter table public.game_results drop constraint game_results_game_check;
alter table public.game_results add  constraint game_results_game_check
  check (game in ('stars', 'duo', 'trail', 'quint'));

-- ---------------------------------------------------------------------------
-- Board with 'quint' in the game picker (body identical to 0006 otherwise)
-- ---------------------------------------------------------------------------

create or replace function public.board(kind text, scope_id uuid, period text, for_date date, game_kind text default 'lineup')
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
  if game_kind not in ('lineup', 'stars', 'duo', 'trail', 'quint', 'total') then
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
-- start_game: 'quint' added to the allowed game list (body otherwise unchanged)
-- ---------------------------------------------------------------------------

create or replace function public.start_game(d date, g text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  row_ daily_games%rowtype;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if g not in ('stars', 'duo', 'trail', 'quint') then raise exception 'bad game' using errcode = '22023'; end if;
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
