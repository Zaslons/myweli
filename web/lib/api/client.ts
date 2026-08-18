import 'server-only';

import createClient from "openapi-fetch";
import { resolvePublicApiBase } from "../api-base";
import type { paths } from "./schema";

/// Typed Myweli API client — types are generated from docs/api/openapi.yaml
/// (`npm run gen:api`). Base URL from env; the localhost default is
/// development-only (see `lib/api-base.ts`), because the callers of this client
/// degrade to empty results rather than failing, and the ISR pages call them
/// during `next build`.
///
/// ## Why `server-only` (2026-08-18)
///
/// The browser never calls the API host — every browser request goes to a
/// same-origin `/api/*` route handler (72 of them) which calls the API from the
/// server. That property is what lets the staging backend keep an exact-match
/// `WEB_ORIGINS` allowlist with no Vercel preview origin in it, now that Preview
/// deployments point at staging (docs/LAUNCH.md §5.4). Vercel mints a distinct
/// hostname per deployment, so an exact-match list could never cover them; the
/// only reason it does not have to is this file.
///
/// The property was true but **unenforced**, and it was quietly eroding: this
/// module was already reaching four production client chunks (via pure helpers
/// that happened to live next to a fetcher), with `createClient()`'s return
/// value discarded. One `api.GET(...)` in a client component would have turned
/// that dead weight into a live cross-origin request, and the failure would
/// have been an opaque CORS error in a preview — while `providers.ts` and
/// `localities.ts` swallow errors and return `[]`, so it would have rendered as
/// an empty marketplace with nothing in the logs.
///
/// `server-only` turns that from a runtime surprise into a **build failure that
/// names the file**. It is one line, and it is the guard the CORS decision
/// rests on.
const baseUrl = resolvePublicApiBase();

export const api = createClient<paths>({ baseUrl });
