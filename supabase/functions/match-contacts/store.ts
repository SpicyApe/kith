// store.ts — Supabase-backed MatchStore. Not a contract file; the handler only
// depends on the `MatchStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { MatchStore } from "./handler.ts";

const CHUNK_SIZE = 1000;

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

export class SupabaseMatchStore implements MatchStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async getDiscoverable(userId: string): Promise<boolean | null> {
    const { data, error } = await this.client
      .from("users")
      .select("discoverable")
      .eq("id", userId)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return data.discoverable;
  }

  async syncUsage(userId: string, since: Date): Promise<{ fullSyncs: number; hashes: number; requests: number }> {
    const { data, error } = await this.client
      .rpc("sync_usage", { u: userId, since: since.toISOString() })
      .single();
    if (error) throw error;
    const row = data as { full_syncs: number; hashes: number; requests: number };
    return { fullSyncs: row.full_syncs, hashes: row.hashes, requests: row.requests };
  }

  async logSync(userId: string, at: Date, hashes: number, full: boolean): Promise<void> {
    const { error } = await this.client.from("contact_sync_log").insert({
      user_id: userId,
      at: at.toISOString(),
      hashes,
      is_full: full,
    });
    if (error) throw error;
  }

  async replaceContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    const { error: deleteError } = await this.client
      .from("contact_hashes")
      .delete()
      .eq("owner_id", userId);
    if (deleteError) throw deleteError;

    for (const batch of chunk(hmacs, CHUNK_SIZE)) {
      if (batch.length === 0) continue;
      const { error } = await this.client
        .from("contact_hashes")
        .insert(batch.map((contact_hmac) => ({ owner_id: userId, contact_hmac })));
      if (error) throw error;
    }
  }

  async upsertContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    for (const batch of chunk(hmacs, CHUNK_SIZE)) {
      if (batch.length === 0) continue;
      const { error } = await this.client
        .from("contact_hashes")
        .upsert(
          batch.map((contact_hmac) => ({ owner_id: userId, contact_hmac })),
          { onConflict: "owner_id,contact_hmac", ignoreDuplicates: true },
        );
      if (error) throw error;
    }
  }

  async deleteContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    for (const batch of chunk(hmacs, CHUNK_SIZE)) {
      if (batch.length === 0) continue;
      const { error } = await this.client
        .from("contact_hashes")
        .delete()
        .eq("owner_id", userId)
        .in("contact_hmac", batch);
      if (error) throw error;
    }
  }

  async countContactHmacs(userId: string): Promise<number> {
    const { count, error } = await this.client
      .from("contact_hashes")
      .select("*", { count: "exact", head: true })
      .eq("owner_id", userId);
    if (error) throw error;
    return count ?? 0;
  }

  async recomputeMatches(userId: string): Promise<void> {
    const { error } = await this.client.rpc("recompute_matches", { owner: userId });
    if (error) throw error;
  }

  async mutualFriends(userId: string): Promise<{ userId: string; displayName: string; phoneHmac: string }[]> {
    const { data: matchRows, error: matchError } = await this.client
      .from("matches")
      .select("user_a, user_b")
      .eq("mutual", true)
      .or(`user_a.eq.${userId},user_b.eq.${userId}`);
    if (matchError) throw matchError;

    const otherIds = (matchRows ?? []).map((m) => (m.user_a === userId ? m.user_b : m.user_a));
    if (otherIds.length === 0) return [];

    const { data: userRows, error: userError } = await this.client
      .from("users")
      .select("id, display_name, phone_hmac")
      .in("id", otherIds);
    if (userError) throw userError;

    return (userRows ?? []).map((u) => ({
      userId: u.id,
      displayName: u.display_name,
      phoneHmac: u.phone_hmac,
    }));
  }
}
