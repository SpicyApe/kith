// store.ts — Supabase-backed SubmitGameStore. Not a contract file; the handler only
// depends on the `SubmitGameStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { GameKind } from "../_shared/games/common.ts";
import { SubmitGameStoreError, type StoredGameResult, type SubmitGameStore } from "./handler.ts";

function rowToResult(data: Record<string, unknown>): StoredGameResult {
  return {
    date: data.date as string,
    game: data.game as GameKind,
    elapsedMs: data.elapsed_ms as number,
    elapsedSource: data.elapsed_source as "server" | "client",
    mistakes: data.mistakes as number,
    solved: data.solved as boolean,
    gaveUp: data.gave_up as boolean,
    score: data.score as number,
    submittedAt: data.submitted_at as string,
  };
}

export class SupabaseSubmitGameStore implements SubmitGameStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async getGame(
    date: string,
    game: GameKind,
  ): Promise<{ spec: unknown; solution: unknown } | null> {
    const { data, error } = await this.client
      .from("daily_games")
      .select("spec, solution")
      .eq("date", date)
      .eq("game", game)
      .eq("status", "approved")
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return { spec: data.spec, solution: data.solution };
  }

  async getStart(userId: string, date: string, game: GameKind): Promise<Date | null> {
    const { data, error } = await this.client
      .from("game_starts")
      .select("started_at")
      .eq("user_id", userId)
      .eq("date", date)
      .eq("game", game)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return new Date(data.started_at);
  }

  async getResult(userId: string, date: string, game: GameKind): Promise<StoredGameResult | null> {
    const { data, error } = await this.client
      .from("game_results")
      .select("date, game, elapsed_ms, elapsed_source, mistakes, solved, gave_up, score, submitted_at")
      .eq("user_id", userId)
      .eq("date", date)
      .eq("game", game)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return rowToResult(data);
  }

  async insertResult(
    userId: string,
    row: Omit<StoredGameResult, "submittedAt"> & { tz: string; submittedAt: Date },
  ): Promise<void> {
    const { error } = await this.client.from("game_results").insert({
      user_id: userId,
      date: row.date,
      game: row.game,
      elapsed_ms: row.elapsedMs,
      elapsed_source: row.elapsedSource,
      mistakes: row.mistakes,
      solved: row.solved,
      gave_up: row.gaveUp,
      score: row.score,
      tz: row.tz,
      submitted_at: row.submittedAt.toISOString(),
    });
    if (error) {
      if (error.code === "23505") {
        throw new SubmitGameStoreError("duplicate");
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
