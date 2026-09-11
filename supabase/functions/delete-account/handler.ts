// delete-account — immediate, in-app account deletion (docs/02 §9, docs/04 §3).
//
// CONTRACT FILE. The real deletion happens in SQL: `delete_account(u)` hands
// owned circles to their oldest other member (or deletes empty ones), drops
// the user from any taunt's `hidden_by`, and deletes the `auth.users` row
// itself, which cascades users → results, reactions, taunts, contact_hashes,
// matches, devices, circle_members, puzzle_starts, sync log. `store.prepare`
// below calls that RPC. `store.deleteAuthUser` (the admin API) is only a
// best-effort follow-up against the auth service's own bookkeeping; its
// "User not found" is treated as success since `prepare` already did the
// real deletion.

import type { Outcome, RequestContext } from "../_shared/context.ts";

export interface DeleteResponse {
  deleted: true;
}

export interface DeleteStore {
  /** `public.delete_account(u)`. Does the real deletion (including auth.users); must be idempotent. */
  prepare(userId: string): Promise<void>;
  /** Best-effort follow-up: Supabase admin API `auth.admin.deleteUser(userId)`. Resolves normally if the user is already gone. */
  deleteAuthUser(userId: string): Promise<void>;
}

/**
 * Behaviour: body is ignored. `store.prepare(ctx.userId)` then
 * `store.deleteAuthUser(ctx.userId)`; any thrown error propagates (index.ts → 500)
 * so the client can retry; both steps are idempotent. Returns 200 `{ deleted: true }`.
 */
export async function handleDelete(
  _body: unknown,
  ctx: RequestContext,
  store: DeleteStore,
): Promise<Outcome<DeleteResponse>> {
  await store.prepare(ctx.userId);
  await store.deleteAuthUser(ctx.userId);
  return { status: 200, body: { deleted: true } };
}
