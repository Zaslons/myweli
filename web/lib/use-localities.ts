'use client';

import { useCallback, useEffect, useState } from 'react';
import type { LocalityTree } from './api/localities';
import { emptyTree } from './api/localities';

/// Client-side locality tree (multi-pays MP3): one fetch of /api/localities
/// per page load, shared across every consumer (pickers, operator catalogs,
/// the salon-time hint label) via a module cache. Consumers render the four
/// states from { tree, loading, error } and call retry() on the error CTA.

let cache: LocalityTree | null = null;
let inflight: Promise<LocalityTree> | null = null;

async function fetchTree(): Promise<LocalityTree> {
  const r = await fetch('/api/localities');
  if (!r.ok) throw new Error(`localities ${r.status}`);
  const body = (await r.json()) as LocalityTree;
  if (!Array.isArray(body.countries)) throw new Error('localities shape');
  return body;
}

function loadTree(): Promise<LocalityTree> {
  inflight ??= fetchTree()
    .then((tree) => {
      cache = tree;
      return tree;
    })
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

/// Test seam: reset the module cache between tests.
export function resetLocalitiesClientCache(): void {
  cache = null;
  inflight = null;
}

export function useLocalities(): {
  tree: LocalityTree;
  loading: boolean;
  error: boolean;
  retry: () => void;
} {
  const [tree, setTree] = useState<LocalityTree | null>(cache);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (cache) {
      setTree(cache);
      return;
    }
    let alive = true;
    setError(false);
    loadTree().then(
      (t) => {
        if (alive) setTree(t);
      },
      () => {
        if (alive) setError(true);
      },
    );
    return () => {
      alive = false;
    };
  }, [attempt]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);

  return {
    tree: tree ?? emptyTree,
    loading: tree === null && !error,
    error,
    retry,
  };
}
