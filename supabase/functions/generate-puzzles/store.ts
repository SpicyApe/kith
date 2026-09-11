// store.ts — Supabase-backed GenerateStore. Not a contract file; the handler
// only depends on the `GenerateStore` interface from handler.ts.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import {
  addDaysUTC,
  ITEM_COOLDOWN_DAYS,
  type GeneratedPuzzle,
  type GenerateStore,
  type ItemRow,
  type ListRow,
  type Usage,
} from "./handler.ts";

export class SupabaseGenerateStore implements GenerateStore {
  private client: SupabaseClient;

  constructor(supabaseUrl: string, serviceRoleKey: string) {
    this.client = createClient(supabaseUrl, serviceRoleKey);
  }

  async lists(): Promise<ListRow[]> {
    const { data, error } = await this.client
      .from("lists")
      .select("id, prompt_template, direction, ascending, enabled");
    if (error) throw error;
    return (data ?? []).map((row) => ({
      id: row.id as number,
      promptTemplate: row.prompt_template as string,
      direction: row.direction as string,
      ascending: row.ascending as boolean,
      enabled: row.enabled as boolean,
    }));
  }

  async items(): Promise<ItemRow[]> {
    const rows: Record<string, unknown>[] = [];
    let offset = 0;
    const PAGE = 1000;
    for (;;) {
      const { data, error } = await this.client
        .from("list_items")
        .select("id, list_id, label, value, familiarity")
        .range(offset, offset + PAGE - 1);
      if (error) throw error;
      const page = data ?? [];
      rows.push(...page);
      if (page.length < PAGE) break;
      offset += PAGE;
    }
    return rows.map((row) => ({
      id: row.id as number,
      listId: row.list_id as number,
      label: row.label as string,
      value: Number(row.value),
      familiarity: row.familiarity as 1 | 2 | 3,
    }));
  }

  async usage(from: string): Promise<Usage> {
    const since = addDaysUTC(from, -ITEM_COOLDOWN_DAYS);
    const { data, error } = await this.client
      .from("puzzles")
      .select("date, list_id, item_ids")
      .gte("date", since);
    if (error) throw error;

    const listUses: { listId: number; date: string }[] = [];
    const itemUses: { itemId: number; date: string }[] = [];
    for (const row of data ?? []) {
      const date = row.date as string;
      listUses.push({ listId: row.list_id as number, date });
      for (const itemId of (row.item_ids as number[]) ?? []) {
        itemUses.push({ itemId, date });
      }
    }
    return { listUses, itemUses };
  }

  async existingDates(from: string, to: string): Promise<string[]> {
    const { data, error } = await this.client
      .from("puzzles")
      .select("date")
      .gte("date", from)
      .lte("date", to);
    if (error) throw error;
    return (data ?? []).map((row) => row.date as string);
  }

  async nextNumber(): Promise<number> {
    const { data, error } = await this.client
      .from("puzzles")
      .select("number")
      .order("number", { ascending: false })
      .limit(1);
    if (error) throw error;
    const max = data && data.length > 0 ? (data[0].number as number) : 0;
    return max + 1;
  }

  async insert(p: GeneratedPuzzle, number: number): Promise<void> {
    const { error } = await this.client.from("puzzles").insert({
      date: p.date,
      number,
      list_id: p.listId,
      item_ids: p.itemIds,
      correct_order: p.correctOrder,
      status: "pending",
      difficulty: p.difficulty,
      seed: p.seed,
    });
    if (error) throw error;
  }

  async replace(p: GeneratedPuzzle): Promise<void> {
    const { data, error } = await this.client
      .from("puzzles")
      .update({
        list_id: p.listId,
        item_ids: p.itemIds,
        correct_order: p.correctOrder,
        difficulty: p.difficulty,
        seed: p.seed,
      })
      .eq("date", p.date)
      .eq("status", "pending")
      .select("date");
    if (error) throw error;
    if (!data || data.length === 0) {
      throw Object.assign(new Error("not pending"), { code: "not_pending" });
    }
  }

  async seedOf(date: string): Promise<number | null> {
    const { data, error } = await this.client
      .from("puzzles")
      .select("seed")
      .eq("date", date)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return data.seed as number;
  }
}
