-- 0004 — the caller-scoped wrappers were granted to `authenticated` in 0001 but
-- never revoked from PUBLIC, so the anon key could execute the zero-argument
-- my_streak() (it returned 0: auth.uid() is null for anon). Close that for every
-- wrapper; the authenticated grants stand.
revoke all on function public.my_streak()              from public, anon;
revoke all on function public.can_see(uuid)            from public, anon;
revoke all on function public.is_circle_member(uuid)   from public, anon;
revoke all on function public.hide_taunt(uuid, date)   from public, anon;
revoke all on function public.sync_usage(uuid, timestamptz) from public, anon;
grant execute on function public.my_streak(), public.can_see(uuid), public.is_circle_member(uuid),
                          public.hide_taunt(uuid, date) to authenticated;
