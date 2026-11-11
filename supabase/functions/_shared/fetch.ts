// fetch with a time limit (11 Nov 2026, the backend sweep). No outside call in these functions had one: a service that hung
// (Semaphore, Cloudinary, Google, a browser's push service, or the database's own API) held the function until the platform
// stopped it. Each module takes its own `const fetch = timedFetch(ms)`, so every call it makes gives up after `ms`.
// It calls globalThis.fetch at the moment of the call, not at import, so the tests' stub (_test/stub.ts) still answers.
// A signal the caller passes wins over the time limit.
export function timedFetch(ms = 10_000): typeof fetch {
  return ((input: string | URL | Request, init: RequestInit = {}) =>
    globalThis.fetch(input, { ...init, signal: init.signal ?? AbortSignal.timeout(ms) })) as typeof fetch;
}
