-- 0009_avatars_streak.sql — profile pictures and a per-player streak on the board.
--
-- Pictures: one JPEG per user in the public Storage bucket `avatars`, at `<user id>.jpg`.
-- The object path is the user id, so `users.avatar_version` is the only thing the table
-- stores: 0 means "no picture", every upload bumps it, and clients build
-- `<project>/storage/v1/object/public/avatars/<id>.jpg?v=<version>` so caches drop the old
-- image. The bucket and its policies are created only when the storage schema exists
-- (the pglite schema check has no Supabase Storage).
--
-- Board: `board()` also returns each member's current streak and avatar_version. The
-- return type changes again, so drop + create + regrant (see 0008 for the shape).

alter table public.users add column if not exists avatar_version int not null default 0
  check (avatar_version >= 0);

grant select (avatar_version) on public.users to authenticated;
grant update (avatar_version) on public.users to authenticated;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', true, 1048576, array['image/jpeg'])
    on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg'];

    -- Anyone can read (the bucket is public); only the owner writes their own `<id>.jpg`.
    drop policy if exists avatars_read on storage.objects;
    create policy avatars_read on storage.objects for select
      using (bucket_id = 'avatars');
    drop policy if exists avatars_insert_own on storage.objects;
    create policy avatars_insert_own on storage.objects for insert to authenticated
      with check (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
    drop policy if exists avatars_update_own on storage.objects;
    create policy avatars_update_own on storage.objects for update to authenticated
      using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg')
      with check (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
    drop policy if exists avatars_delete_own on storage.objects;
    create policy avatars_delete_own on storage.objects for delete to authenticated
      using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- board(): + streak, avatar_version
-- ---------------------------------------------------------------------------

drop function public.board(text, uuid, text, date, text);

create function public.board(kind text, scope_id uuid, period text, for_date date, game_kind text default 'lineup')
returns table (
  user_id uuid, display_name text, score int, tries smallint, elapsed_ms int,
  attempts jsonb, played boolean, rank int, prev_rank int,
  solved_count int, played_count int,
  prev_score int, prev_played boolean, prev_elapsed_ms int, prev_solved_count int, prev_played_count int,
  streak int, avatar_version int
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
           p.solved_count as prev_solved_count, p.played_count as prev_played_count,
           public.streak(c.id) as streak, u.avatar_version
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
         p.solved_count as prev_solved_count, p.played_count as prev_played_count,
         public.streak(c.id) as streak, u.avatar_version
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
