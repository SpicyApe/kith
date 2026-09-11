// send-pushes — runs every 15 minutes from pg_cron (see migrations/0002_cron.sql).
//
// CONTRACT FILE. The SQL function `push_candidates(at)` decides WHO gets WHAT
// (timezone windows, caps, preferences). This handler turns each candidate into
// copy, sends it, logs it, and prunes dead tokens. Pure over PushStore + a sender.

import type { ApnsPayload, ApnsResult } from "../_shared/apns.ts";

export type PushKind = "daily_drop" | "streak_risk" | "passed";

export interface PushCandidate {
  userId: string;
  kind: PushKind;
  apnsToken: string;
  env: "sandbox" | "production";
  /** From push_candidates: daily_drop {friendsPlayed}, streak_risk {streak, hoursLeft}, passed {by, others, rank}. */
  payload: Record<string, unknown>;
}

export interface PushStore {
  /** `public.push_candidates(at)` rows. */
  candidates(at: Date): Promise<PushCandidate[]>;
  /** Insert into notification_log. Called once per USER per kind, not per device. */
  log(userId: string, kind: PushKind, at: Date): Promise<void>;
  /** Delete the device row after APNs says the token is dead. */
  deleteDevice(userId: string, apnsToken: string): Promise<void>;
}

export interface PushSender {
  send(env: "sandbox" | "production", apnsToken: string, payload: ApnsPayload): Promise<ApnsResult>;
}

export interface SendReport {
  /** Distinct (user, kind) pairs that had at least one successful device send. */
  sent: number;
  /** Device sends that failed for a non-token reason. */
  failed: number;
  /** Tokens deleted. */
  deadTokens: number;
}

/**
 * Copy per kind (docs/02 §7), deterministic, no random variants:
 *  daily_drop:  title "Today's Lineup is up."
 *               body  friendsPlayed === 0 → "Be the first of your friends to play."
 *                     friendsPlayed === 1 → "1 friend has already played."
 *                     n                    → "<n> friends have already played."
 *               url "kith://today"
 *  streak_risk: title "<streak>-day streak on the line."
 *               body  hoursLeft <= 1 → "Less than an hour left." else "<hoursLeft> hours left."
 *               url "kith://today"
 *  passed:      title "<by> just passed you."
 *               body  others === 0 → "You're #<rank> among friends."
 *                     others === 1 → "<by> and 1 other passed you. You're #<rank> among friends."
 *                     n            → "<by> and <n> others passed you. You're #<rank> among friends."
 *               url "kith://board"
 * `kind` is copied into the payload. Missing/invalid numbers are treated as 0; missing `by` as "A friend".
 */
function numberOr0(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

function stringOrDefault(v: unknown, fallback: string): string {
  return typeof v === "string" ? v : fallback;
}

export function pushCopy(kind: PushKind, payload: Record<string, unknown>): ApnsPayload {
  switch (kind) {
    case "daily_drop": {
      const friendsPlayed = numberOr0(payload.friendsPlayed);
      const body = friendsPlayed === 0
        ? "Be the first of your friends to play."
        : friendsPlayed === 1
        ? "1 friend has already played."
        : `${friendsPlayed} friends have already played.`;
      return { title: "Today's Lineup is up.", body, url: "kith://today", kind };
    }
    case "streak_risk": {
      const streak = numberOr0(payload.streak);
      const hoursLeft = numberOr0(payload.hoursLeft);
      const body = hoursLeft <= 1 ? "Less than an hour left." : `${hoursLeft} hours left.`;
      return { title: `${streak}-day streak on the line.`, body, url: "kith://today", kind };
    }
    case "passed": {
      const by = stringOrDefault(payload.by, "A friend");
      const others = numberOr0(payload.others);
      const rank = numberOr0(payload.rank);
      const body = others === 0
        ? `You're #${rank} among friends.`
        : others === 1
        ? `${by} and 1 other passed you. You're #${rank} among friends.`
        : `${by} and ${others} others passed you. You're #${rank} among friends.`;
      return { title: `${by} just passed you.`, body, url: "kith://board", kind };
    }
  }
}

/**
 * Behaviour:
 * 1. cands = store.candidates(now).
 * 2. Group by (userId, kind). For each group, send to every device (sequentially is fine).
 *    - ok → mark the group sent.
 *    - bad_token → store.deleteDevice; deadTokens++.
 *    - error → failed++ (do not retry; the next run picks the user up again if still eligible).
 * 3. For each group with ≥ 1 ok send, store.log(userId, kind, now) exactly once.
 * 4. Return the report. Never throws for per-device failures; a thrown store.candidates error propagates.
 *
 * store.deleteDevice and store.log are each wrapped in try/catch: a rejection
 * from either counts as failed++ and the loop continues with the next device
 * or group rather than aborting the whole run.
 */
export async function handleSendPushes(
  now: Date,
  store: PushStore,
  sender: PushSender,
): Promise<SendReport> {
  const candidates = await store.candidates(now);

  const groups = new Map<string, { userId: string; kind: PushKind; candidates: PushCandidate[] }>();
  for (const c of candidates) {
    const key = `${c.userId}|${c.kind}`;
    let group = groups.get(key);
    if (!group) {
      group = { userId: c.userId, kind: c.kind, candidates: [] };
      groups.set(key, group);
    }
    group.candidates.push(c);
  }

  let sent = 0;
  let failed = 0;
  let deadTokens = 0;

  for (const group of groups.values()) {
    let anyOk = false;
    for (const c of group.candidates) {
      const payload = pushCopy(c.kind, c.payload);
      const result = await sender.send(c.env, c.apnsToken, payload);
      if (result.ok) {
        anyOk = true;
      } else if (result.reason === "bad_token") {
        try {
          await store.deleteDevice(c.userId, c.apnsToken);
          deadTokens++;
        } catch {
          failed++;
        }
      } else {
        failed++;
      }
    }
    if (anyOk) {
      sent++;
      try {
        await store.log(group.userId, group.kind, now);
      } catch {
        failed++;
      }
    }
  }

  return { sent, failed, deadTokens };
}
