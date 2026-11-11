import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.19";
import { timedFetch } from "./fetch.ts";

// A service that never answers: the call is abandoned when the time limit passes.
Deno.test("timedFetch abandons a call that never answers", async () => {
  const original = globalThis.fetch;
  let sawSignal = false;
  globalThis.fetch = ((_input: string | URL | Request, init: RequestInit = {}) =>
    new Promise<Response>((_resolve, reject) => {
      sawSignal = init.signal instanceof AbortSignal;
      init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
    })) as typeof fetch;
  try {
    const started = Date.now();
    await assertRejects(() => timedFetch(50)("https://example.invalid/"));
    assert(sawSignal, "the call carried a signal");
    assert(Date.now() - started < 2000, "it gave up quickly");
  } finally {
    globalThis.fetch = original;
  }
});

// A service that answers in time: the answer comes through untouched, and a caller's own signal is kept.
Deno.test("timedFetch passes an answer through and keeps the caller's signal", async () => {
  const original = globalThis.fetch;
  const mine = new AbortController();
  let got: AbortSignal | null | undefined;
  globalThis.fetch = ((_input: string | URL | Request, init: RequestInit = {}) => {
    got = init.signal;
    return Promise.resolve(new Response("ok", { status: 200 }));
  }) as typeof fetch;
  try {
    const res = await timedFetch(50)("https://example.invalid/", { signal: mine.signal });
    assertEquals(await res.text(), "ok");
    assert(got === mine.signal, "the caller's signal was used");
  } finally {
    globalThis.fetch = original;
  }
});
