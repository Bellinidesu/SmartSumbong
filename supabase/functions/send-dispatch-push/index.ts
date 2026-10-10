// Entry point: the logic is in handler.ts, where the tests (handler.test.ts)
// can reach it without starting a server.
import { handler } from "./handler.ts";

Deno.serve(handler);
