import createClient from "openapi-fetch";
import { resolvePublicApiBase } from "../api-base";
import type { paths } from "./schema";

/// Typed Myweli API client — types are generated from docs/api/openapi.yaml
/// (`npm run gen:api`). Base URL from env; the localhost default is
/// development-only (see `lib/api-base.ts`), because the callers of this client
/// degrade to empty results rather than failing, and the ISR pages call them
/// during `next build`.
const baseUrl = resolvePublicApiBase();

export const api = createClient<paths>({ baseUrl });
