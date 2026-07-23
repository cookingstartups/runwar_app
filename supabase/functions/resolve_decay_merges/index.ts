// Thin entrypoint, matching every other function under supabase/functions/:
// Deno.serve is called unconditionally at module top level. The request
// handler lives in handler.ts, which a test can import directly without
// pulling in this module's Deno.serve() side effect.
import { handleResolveDecayMergesRequest } from './handler.ts';

Deno.serve(handleResolveDecayMergesRequest);
