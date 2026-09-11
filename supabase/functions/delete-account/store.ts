// store.ts — Supabase-backed DeleteStore. Not a contract file; the handler only
// depends on the `DeleteStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { DeleteStore } from "./handler.ts";

export class SupabaseDeleteStore implements DeleteStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async prepare(userId: string): Promise<void> {
    const { error } = await this.client.rpc("delete_account", { u: userId });
    if (error) throw error;
  }

  async deleteAuthUser(userId: string): Promise<void> {
    const { error } = await this.client.auth.admin.deleteUser(userId);
    if (error) {
      if (/user not found/i.test(error.message ?? "")) return;
      throw error;
    }
  }
}
