// Tests for context.ts, written strictly against its doc comments.
// context.ts is already implemented, so these must PASS today.

import { assertEquals } from "jsr:@std/assert";
import { asObject, dateWithinWindow, isValidTimeZone, requireString } from "./context.ts";

// ---------------------------------------------------------------------------
// dateWithinWindow
// ---------------------------------------------------------------------------

const NOW = new Date("2026-09-11T12:00:00Z");

Deno.test("dateWithinWindow - lower boundary date (now - 14h) is accepted", () => {
  assertEquals(dateWithinWindow("2026-09-10", NOW), true);
});

Deno.test("dateWithinWindow - the day before the lower boundary is rejected", () => {
  assertEquals(dateWithinWindow("2026-09-09", NOW), false);
});

Deno.test("dateWithinWindow - today is always accepted", () => {
  assertEquals(dateWithinWindow("2026-09-11", NOW), true);
});

Deno.test("dateWithinWindow - upper boundary date (now + 14h) is accepted", () => {
  assertEquals(dateWithinWindow("2026-09-12", NOW), true);
});

Deno.test("dateWithinWindow - the day after the upper boundary is rejected", () => {
  assertEquals(dateWithinWindow("2026-09-13", NOW), false);
});

Deno.test("dateWithinWindow - ahead precision: tomorrow's midnight 13h away is accepted, 15h away is not", () => {
  // Tomorrow (2026-09-12) starts 13h after 11:00 -> now+14h crosses into it.
  const now13 = new Date("2026-09-11T11:00:00Z");
  assertEquals(dateWithinWindow("2026-09-12", now13), true);
  // Tomorrow starts 15h after 09:00 -> now+14h stops short of it.
  const now15 = new Date("2026-09-11T09:00:00Z");
  assertEquals(dateWithinWindow("2026-09-12", now15), false);
});

Deno.test("dateWithinWindow - behind precision: yesterday reachable when now is 13h past midnight, not at 15h", () => {
  // now-14h dips back into yesterday (2026-09-10) when now is 13:00.
  const nowBehind13 = new Date("2026-09-11T13:00:00Z");
  assertEquals(dateWithinWindow("2026-09-10", nowBehind13), true);
  // At 15:00, now-14h is still within today, so yesterday is out of range.
  const nowBehind15 = new Date("2026-09-11T15:00:00Z");
  assertEquals(dateWithinWindow("2026-09-10", nowBehind15), false);
});

Deno.test("dateWithinWindow - rejects malformed date strings regardless of window", () => {
  assertEquals(dateWithinWindow("2026-9-11", NOW), false); // not zero-padded
  assertEquals(dateWithinWindow("2026/09/11", NOW), false); // wrong separators
  assertEquals(dateWithinWindow("20260911", NOW), false); // no separators
  assertEquals(dateWithinWindow("", NOW), false); // empty
  assertEquals(dateWithinWindow("2026-09-11T00:00:00Z", NOW), false); // has a time component
});

// ---------------------------------------------------------------------------
// isValidTimeZone
// ---------------------------------------------------------------------------

Deno.test("isValidTimeZone - accepts UTC", () => {
  assertEquals(isValidTimeZone("UTC"), true);
});

Deno.test("isValidTimeZone - accepts America/New_York", () => {
  assertEquals(isValidTimeZone("America/New_York"), true);
});

Deno.test("isValidTimeZone - accepts Europe/London", () => {
  assertEquals(isValidTimeZone("Europe/London"), true);
});

Deno.test("isValidTimeZone - rejects an unknown zone name", () => {
  assertEquals(isValidTimeZone("Mars/Olympus"), false);
});

Deno.test("isValidTimeZone - rejects an empty string", () => {
  assertEquals(isValidTimeZone(""), false);
});

Deno.test("isValidTimeZone - rejects a string longer than 64 characters", () => {
  const longTz = "A".repeat(70);
  assertEquals(isValidTimeZone(longTz), false);
});

Deno.test("isValidTimeZone - rejects a non-string value", () => {
  assertEquals(isValidTimeZone(123 as unknown as string), false);
});

// ---------------------------------------------------------------------------
// asObject / requireString
// ---------------------------------------------------------------------------

Deno.test("asObject - a plain object passes through unchanged", () => {
  const o = { a: 1 };
  assertEquals(asObject(o), o);
});

Deno.test("asObject - null returns null", () => {
  assertEquals(asObject(null), null);
});

Deno.test("asObject - a non-object primitive returns null", () => {
  assertEquals(asObject("x"), null);
});

Deno.test("requireString - a present string value is returned", () => {
  assertEquals(requireString({ k: "v" }, "k"), "v");
});

Deno.test("requireString - a missing key returns null", () => {
  assertEquals(requireString({}, "k"), null);
});

Deno.test("requireString - a non-string value returns null", () => {
  assertEquals(requireString({ k: 5 }, "k"), null);
});
