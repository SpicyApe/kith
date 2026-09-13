-- 0008_board_prev_score.sql — the board also describes the previous window.
--
-- The client board now shows today and yesterday side by side as solve TIMES (docs/02 §5
-- update, 2026-09-13): no week / all-time periods and no Everyone board in the client. So
-- `board()` gains, for both windows, the summed elapsed time, how many games were played
-- and how many were solved, plus the previous window's score. The return type changes,
-- which `create or replace` cannot do, so the function is dropped and recreated and its
-- grants restated. Ranking inside the function is unchanged (score, then time); the client
-- re-ranks per section by time (docs/07 §Boards).
--
-- New columns:
--   solved_count / played_count           games solved / played in the current window
--   prev_score, prev_played, prev_elapsed_ms, prev_solved_count, prev_played_count
--                                         the same for the previous window (yesterday for
--                                         period 'today'); prev_elapsed_ms is null when
--                                         nothing was played.
-- `elapsed_ms` keeps its meaning (current window, 'today' only) so existing clients decode.

drop function public.board(text, uuid, text, date, text);

create function public.board(kind text, scope_id uuid, period text, for_date date, game_kind text default 'lineup')
returns table (
  user_id uuid, display_name text, score int, tries smallint, elapsed_ms int,
  attempts jsonb, played boolean, rank int, prev_rank int,
  solved_count int, played_count int,
  prev_score int, prev_played boolean, prev_elapsed_ms int, prev_solved_count int, prev_played_count int
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
    select r.user_id, r.puzzle_date as date, r.score, r.elapsed_ms, r.tries, r.attempts, r.submitted_at, r.solved
    from results r
    where game_kind in ('lineup', 'total') and r.puzzle_date between p_from and d_to
    union all
    select g.user_id, g.date, g.score, g.elapsed_ms, null::smallint, null::jsonb, g.submitted_at, g.solved
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
           min(s.submitted_at) filter (where period = 'today') as submitted_at,
           count(s.user_id) filter (where s.solved)::int as solved_count,
           count(s.user_id)::int as played_count
    from members m
    left join scores s on s.user_id = m.id and s.date between d_from and d_to
    group by m.id
  ),
  prev as (
    select m.id, coalesce(sum(s.score), 0)::int as score,
           bool_or(s.user_id is not null) as played,
           sum(s.elapsed_ms) filter (where period = 'today')::int as elapsed_ms,
           count(s.user_id) filter (where s.solved)::int as solved_count,
           count(s.user_id)::int as played_count
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
           c.played, rk.rank::int as rank, pr.rank::int as prev_rank,
           c.solved_count, c.played_count,
           p.score as prev_score, p.played as prev_played, p.elapsed_ms as prev_elapsed_ms,
           p.solved_count as prev_solved_count, p.played_count as prev_played_count
    from cur c
    join users u on u.id = c.id
    join ranked rk on rk.id = c.id
    left join prev_ranked pr on pr.id = c.id
    left join prev p on p.id = c.id
    order by c.played desc, c.score desc, c.elapsed_ms asc nulls last, c.submitted_at asc nulls last
    limit case when kind = 'everyone' then 100 else 1000 end
  ) top
  union all
  select c.id, u.display_name, c.score, c.tries, c.elapsed_ms, null::jsonb as attempts,
         c.played, rk.rank::int as rank, pr.rank::int as prev_rank,
         c.solved_count, c.played_count,
         p.score as prev_score, p.played as prev_played, p.elapsed_ms as prev_elapsed_ms,
         p.solved_count as prev_solved_count, p.played_count as prev_played_count
  from cur c
  join users u on u.id = c.id
  join ranked rk on rk.id = c.id
  left join prev_ranked pr on pr.id = c.id
  left join prev p on p.id = c.id
  where kind = 'everyone' and c.id = me and rk.rank > 100;
end;
$$;

revoke all on function public.board(text, uuid, text, date, text) from public, anon;
grant execute on function public.board(text, uuid, text, date, text) to authenticated;
