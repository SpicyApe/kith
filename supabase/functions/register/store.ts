// store.ts — Supabase-backed RegisterStore. Not a contract file; the handler
// only depends on the `RegisterStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { RegisterStoreError, type RegisterStore } from "./handler.ts";

const MAX_INVITE_CODE_RETRIES = 5;

function mentions(error: { message?: string; details?: string | null }, needle: string): boolean {
  return (error.message?.includes(needle) ?? false) || (error.details?.includes(needle) ?? false);
}

export class SupabaseRegisterStore implements RegisterStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async getUser(userId: string): Promise<{ displayName: string; inviteCode: string } | null> {
    const { data, error } = await this.client
      .from("users")
      .select("display_name, invite_code")
      .eq("id", userId)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return { displayName: data.display_name, inviteCode: data.invite_code };
  }

  async insertUser(
    row: { userId: string; phoneHmac: string; displayName: string; tz: string },
  ): Promise<{ inviteCode: string }> {
    for (let attempt = 0; attempt < MAX_INVITE_CODE_RETRIES; attempt++) {
      const { data, error } = await this.client
        .from("users")
        .insert({
          id: row.userId,
          phone_hmac: row.phoneHmac,
          display_name: row.displayName,
          tz: row.tz,
        })
        .select("invite_code")
        .single();

      if (!error) {
        return { inviteCode: data.invite_code };
      }

      if (error.code === "23505") {
        if (mentions(error, "users_phone_hmac_key")) {
          throw new RegisterStoreError("phone_taken");
        }
        if (mentions(error, "users_invite_code_key")) {
          continue;
        }
        if (mentions(error, "users_pkey")) {
          // Concurrent registers for the same auth user: the other request won
          // the race and already inserted the row. Return its profile instead
          // of surfacing a 500 for what is, from the caller's perspective, success.
          const existing = await this.getUser(row.userId);
          if (existing) return { inviteCode: existing.inviteCode };
        }
      }
      throw new Error(`insert users failed: ${error.code}`);
    }
    throw new Error("invite_code collision retries exhausted");
  }
}
