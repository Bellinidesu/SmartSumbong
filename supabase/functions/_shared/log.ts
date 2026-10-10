// Records an Edge Function failure in portal_errors (source 'function',
// 0119), so it shows under Settings -> System status -> Recent errors and
// raises the hourly health alert. Never throws: logging must not turn one
// failure into two. Only the error's message is kept (no request bodies).
export async function logError(fn: string, e: unknown): Promise<void> {
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return;
    const message = e instanceof Error ? e.message : String(e);
    await fetch(`${url}/rest/v1/rpc/log_portal_error`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_source: "function", p_page: fn, p_message: message.slice(0, 500) }),
    });
  } catch {
    // nothing more to do
  }
}
