// register — creates the `users` row after phone OTP sign-in.
//
// CONTRACT FILE. Pure handler; index.ts supplies ctx (with ctx.phone from the auth
// user) and a Supabase-backed RegisterStore. See docs/02 §9 and docs/04 §3.

import type { Outcome, RequestContext } from "../_shared/context.ts";
import { asObject, err, isValidTimeZone, requireString } from "../_shared/context.ts";
import { phoneToHmac } from "../_shared/hashing.ts";

export interface RegisterRequest {
  displayName: string; // 1..30 chars after trim
  tz: string; // IANA
}

export interface RegisterResponse {
  userId: string;
  displayName: string;
  inviteCode: string;
  /** True when the row already existed (idempotent re-register returns the existing profile unchanged). */
  existing: boolean;
}

export interface RegisterStore {
  /** Existing profile for this user id, or null. */
  getUser(userId: string): Promise<{ displayName: string; inviteCode: string } | null>;
  /**
   * Insert the users row. Must retry internally on invite_code collision (SQLSTATE
   * 23505 on `users_invite_code_key`) up to 5 times, since the code is a DB default.
   * Throws `RegisterStoreError("phone_taken")` if `phoneHmac` is already used by
   * another user id (23505 on `users_phone_hmac_key`).
   */
  insertUser(row: { userId: string; phoneHmac: string; displayName: string; tz: string }): Promise<{ inviteCode: string }>;
}

export class RegisterStoreError extends Error {
  constructor(public code: "phone_taken", message = code) {
    super(message);
    this.name = "RegisterStoreError";
  }
}

/**
 * Behaviour:
 * 1. If `store.getUser(ctx.userId)` exists → 200 `{ existing: true, ... }` without touching the row.
 * 2. Validate body: `displayName` string, trimmed length 1..30 → else 400 `bad_request`;
 *    `tz` valid IANA → else 400 `bad_tz`.
 * 3. `ctx.phone` must canonicalise (see hashing.canonicalPhone) → else 400 `bad_phone`.
 * 4. phoneHmac = phoneToHmac(pepper, ctx.phone); insert; on `phone_taken` → 409 `phone_taken`.
 * 5. 201 `{ existing: false, userId, displayName (trimmed), inviteCode }`.
 * `pepper` is the CONTACT_PEPPER secret; index.ts passes it in. Empty pepper → throw (misconfiguration, not a 4xx).
 */
export async function handleRegister(
  body: unknown,
  ctx: RequestContext,
  store: RegisterStore,
  pepper: string,
): Promise<Outcome<RegisterResponse>> {
  const existing = await store.getUser(ctx.userId);
  if (existing !== null) {
    return {
      status: 200,
      body: {
        existing: true,
        userId: ctx.userId,
        displayName: existing.displayName,
        inviteCode: existing.inviteCode,
      },
    };
  }

  const b = asObject(body);
  const rawDisplayName = b === null ? null : requireString(b, "displayName");
  if (rawDisplayName === null) {
    return err(400, "bad_request", "displayName is required");
  }
  const displayName = rawDisplayName.trim();
  if (displayName.length < 1 || displayName.length > 30) {
    return err(400, "bad_request", "displayName must be 1..30 characters");
  }

  const tz = b === null ? null : requireString(b, "tz");
  if (tz === null || !isValidTimeZone(tz)) {
    return err(400, "bad_tz", "tz must be a valid IANA time zone");
  }

  if (!pepper) throw new Error("empty pepper");

  if (ctx.phone === undefined) {
    return err(400, "bad_phone", "phone could not be canonicalised");
  }

  const phoneHmac = await phoneToHmac(pepper, ctx.phone);
  if (phoneHmac === null) {
    return err(400, "bad_phone", "phone could not be canonicalised");
  }

  try {
    const { inviteCode } = await store.insertUser({
      userId: ctx.userId,
      phoneHmac,
      displayName,
      tz,
    });
    return {
      status: 201,
      body: { existing: false, userId: ctx.userId, displayName, inviteCode },
    };
  } catch (e) {
    if (e instanceof RegisterStoreError && e.code === "phone_taken") {
      return err(409, "phone_taken", "phone number is already registered");
    }
    throw e;
  }
}
