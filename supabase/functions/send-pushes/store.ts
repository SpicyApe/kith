// store.ts — Supabase-backed PushStore. Not a contract file; the handler only
// depends on the `PushStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { PushCandidate, PushKind, PushStore } from "./handler.ts";

export class SupabasePushStore implements PushStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async candidates(at: Date): Promise<PushCandidate[]> {
    const { data, error } = await this.client.rpc("push_candidates", { at: at.toISOString() });
    if (error) throw error;
    return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
      userId: row.user_id as string,
      kind: row.kind as PushKind,
      apnsToken: row.apns_token as string,
      env: row.env as "sandbox" | "production",
      payload: (row.payload ?? {}) as Record<string, unknown>,
    }));
  }

  async log(userId: string, kind: PushKind, at: Date): Promise<void> {
    const { error } = await this.client.from("notification_log").insert({
      user_id: userId,
      kind,
      sent_at: at.toISOString(),
    });
    if (error) throw error;
  }

  async deleteDevice(userId: string, apnsToken: string): Promise<void> {
    const { error } = await this.client
      .from("devices")
      .delete()
      .eq("user_id", userId)
      .eq("apns_token", apnsToken);
    if (error) throw error;
  }
}
