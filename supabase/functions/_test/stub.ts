// Test helper (not deployed: Supabase skips folders starting with "_").
// Replaces fetch with a list of routes, records every call, and fails on
// any request no route answers, so a test sees exactly what a function
// sent to Supabase, Cloudinary or Google.

export type Call = { url: URL; method: string; headers: Headers; body: string };
export type Route = (call: Call) => Response | undefined | Promise<Response | undefined>;

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export function stubFetch(routes: Route[]) {
  const calls: Call[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(input instanceof Request ? input.url : input.toString());
    const body = init.body === undefined || init.body === null ? "" : init.body.toString();
    const call = { url, method: init.method ?? "GET", headers: new Headers(init.headers), body };
    calls.push(call);
    for (const route of routes) {
      const res = await route(call);
      if (res) return res;
    }
    throw new Error(`unexpected request: ${call.method} ${url}`);
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

export function setEnv(values: Record<string, string>) {
  for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
}

export function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}
