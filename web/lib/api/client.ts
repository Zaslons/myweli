import createClient from 'openapi-fetch';
import type { paths } from './schema';

/// Typed Myweli API client — types are generated from docs/api/openapi.yaml
/// (`npm run gen:api`). Base URL from env (dev defaults to the local backend).
const baseUrl =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080';

export const api = createClient<paths>({ baseUrl });
