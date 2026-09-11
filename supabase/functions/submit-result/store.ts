// store.ts — Supabase-backed SubmitStore. Not a contract file; the handler only
// depends on the `SubmitStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { EvaluatedAttempt } from "../_shared/lineup.ts";
import { SubmitStoreError, type StoredResult, type SubmitStore } from "./handler.ts";

function rowToResult(data: Record<string, unknown>): StoredResult {
  return {
    puzzleDate: data.puzzle_date as string,
    tries: data.tries as number,
    solved: data.solved as boolean,
    elapsedMs: data.elapsed_ms as number,
    score: data.score as number,
    attempts: data.attempts as EvaluatedAttempt[],
    elapsedSource: data.elapsed_source as "server" | "client",
    submittedAt: data.submitted_at as string,
  };
}

export class SupabaseSubmitStore implements SubmitStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async getPuzzle(date: string): Promise<{ correctOrder: number[] } | null> {
    const { data, error } = await this.client
      .from("puzzles")
      .select("correct_order")
      .eq("date", date)
      .eq("status", "approved")
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return { correctOrder: data.correct_order };
  }

  async getStart(userId: string, date: string): Promise<Date | null> {
    const { data, error } = await this.client
      .from("puzzle_starts")
      .select("started_at")
      .eq("user_id", userId)
      .eq("puzzle_date", date)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return new Date(data.started_at);
  }

  async getResult(userId: string, date: string): Promise<StoredResult | null> {
    const { data, error } = await this.client
      .from("results")
      .select("puzzle_date, tries, solved, elapsed_ms, score, attempts, elapsed_source, submitted_at")
      .eq("user_id", userId)
      .eq("puzzle_date", date)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return rowToResult(data);
  }

  async insertResult(
    userId: string,
    row: Omit<StoredResult, "submittedAt"> & { tz: string; submittedAt: Date },
  ): Promise<void> {
    const { error } = await this.client.from("results").insert({
      user_id: userId,
      puzzle_date: row.puzzleDate,
      attempts: row.attempts,
      tries: row.tries,
      solved: row.solved,
      elapsed_ms: row.elapsedMs,
      score: row.score,
      tz: row.tz,
      elapsed_source: row.elapsedSource,
      submitted_at: row.submittedAt.toISOString(),
    });
    if (error) {
      if (error.code === "23505") {
        throw new SubmitStoreError("duplicate");
      }
      throw error;
    }
  }

  async streak(userId: string): Promise<number> {
    const { data, error } = await this.client.rpc("streak", { u: userId });
    if (error) throw error;
    return data as number;
  }

  async touchUser(userId: string, tz: string, now: Date): Promise<void> {
    const { error } = await this.client
      .from("users")
      .update({ tz, last_open_at: now.toISOString() })
      .eq("id", userId);
    if (error) {
      if (error.code === "23514") {
        const { error: retryError } = await this.client
          .from("users")
          .update({ last_open_at: now.toISOString() })
          .eq("id", userId);
        if (retryError) throw retryError;
        return;
      }
      throw error;
    }
  }
}
