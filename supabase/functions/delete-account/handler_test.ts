// Tests for delete-account/handler.ts, written strictly against its contract
// doc comments. Store is FakeDeleteStore (in-memory); no real DB or auth API.

import { assertEquals, assertRejects } from "jsr:@std/assert";
import type { RequestContext } from "../_shared/context.ts";
import { FakeDeleteStore } from "../_shared/test_fakes.ts";
import { handleDelete } from "./handler.ts";

function ctx(overrides: Partial<RequestContext> = {}): RequestContext {
  return { userId: "user-1", now: new Date("2026-09-11T12:00:00Z"), ...overrides };
}

Deno.test("handleDelete - happy path: 200 {deleted:true}, prepare called before deleteAuthUser with ctx.userId", async () => {
  const store = new FakeDeleteStore();
  const outcome = await handleDelete(undefined, ctx({ userId: "u1" }), store);

  assertEquals(outcome, { status: 200, body: { deleted: true } });
  assertEquals(store.calls, ["prepare:u1", "deleteAuthUser:u1"]);
  assertEquals(store.prepareCalls, ["u1"]);
  assertEquals(store.deleteAuthUserCalls, ["u1"]);
});

Deno.test("handleDelete - prepare throwing propagates and deleteAuthUser is not called", async () => {
  const store = new FakeDeleteStore();
  store.prepareError = new Error("prepare boom");

  await assertRejects(
    () => handleDelete(undefined, ctx({ userId: "u2" }), store),
    Error,
    "prepare boom",
  );
  assertEquals(store.deleteAuthUserCalls.length, 0);
});

Deno.test("handleDelete - deleteAuthUser throwing propagates after prepare has run", async () => {
  const store = new FakeDeleteStore();
  store.deleteAuthUserError = new Error("delete boom");

  await assertRejects(
    () => handleDelete(undefined, ctx({ userId: "u3" }), store),
    Error,
    "delete boom",
  );
  assertEquals(store.prepareCalls, ["u3"]);
});

Deno.test("handleDelete - body is ignored (a string body still succeeds)", async () => {
  const store = new FakeDeleteStore();
  const outcome = await handleDelete("this is not valid json shape", ctx({ userId: "u4" }), store);

  assertEquals(outcome, { status: 200, body: { deleted: true } });
  assertEquals(store.calls, ["prepare:u4", "deleteAuthUser:u4"]);
});

Deno.test("handleDelete - body is ignored (null body still succeeds)", async () => {
  const store = new FakeDeleteStore();
  const outcome = await handleDelete(null, ctx({ userId: "u5" }), store);
  assertEquals(outcome, { status: 200, body: { deleted: true } });
});
