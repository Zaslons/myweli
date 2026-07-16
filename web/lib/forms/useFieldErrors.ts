'use client';

import { useCallback, useState } from 'react';

/// §14 rule 2, as a hook: **validate on submit; re-validate on change once a
/// field has already errored.** Never validate a field the user hasn't finished
/// typing into — the form that yells « email invalide » at `s@` is hostile.
///
/// Usage (the auth funnels are the reference implementation):
///
///   const { errors, validate, revalidate } = useFieldErrors({
///     email: (v: string) =>
///       /\S+@\S+\.\S+/.test(v) ? null : 'Saisissez une adresse e-mail valide.',
///   });
///   // onChange: setEmail(v); revalidate('email', v);   ← silent until errored
///   // onSubmit: if (!validate({ email })) return;      ← the §14 gate
///
/// Messages say what to DO, not what happened (§14 rule 4), and the submit
/// button stays ENABLED — disabled-as-validation is rule 5's anti-pattern; an
/// invalid submit answers with a field error instead of a dead end.
export function useFieldErrors<K extends string>(
  validators: Record<K, (value: string) => string | null>,
) {
  const [errors, setErrors] = useState<Partial<Record<K, string>>>({});

  /** Validate THE FIELDS YOU PASS (submit time). Returns true when all pass.
   *  Subset-scoped on purpose: a multi-step form (the funnels) submits one
   *  step's fields at a time — validating the phone on the email step would
   *  fail fields the user has never seen. */
  const validate = useCallback(
    (values: Partial<Record<K, string>>) => {
      // MERGE, don't replace: §14 says an error persists until FIXED. A submit
      // that validates {code} must not wipe a still-unfixed businessName error
      // two fields up — the review proved exactly that wipe (and the submit
      // then fired with the empty value).
      const faults: Partial<Record<K, string>> = {};
      for (const key of Object.keys(values) as K[]) {
        const fault = validators[key](values[key] ?? '');
        if (fault) faults[key] = fault;
      }
      setErrors((cur) => {
        const next = { ...cur };
        for (const key of Object.keys(values) as K[]) {
          if (faults[key]) next[key] = faults[key];
          else delete next[key];
        }
        return next;
      });
      // The return covers the subset the CALLER submitted — a stale error on a
      // field from another step neither blocks nor is wiped by this call.
      return Object.keys(faults).length === 0;
    },
    [validators],
  );

  /** Re-run ONE validator, only if that field is currently errored (rule 2). */
  const revalidate = useCallback(
    (key: K, value: string) => {
      setErrors((cur) => {
        if (!(key in cur)) return cur; // not errored — stay silent
        const fault = validators[key](value);
        const next = { ...cur };
        if (fault) next[key] = fault;
        else delete next[key];
        return next;
      });
    },
    [validators],
  );

  /** Attach a SERVER-side fault to its field (§14 rule 1 applies to those too —
   *  « Code incorrect ou expiré » belongs under the code field, not in a toast).
   *  Rule 2 then clears it the moment a changed value passes the client check. */
  const set = useCallback((key: K, message: string | null) => {
    setErrors((cur) => {
      const next = { ...cur };
      if (message) next[key] = message;
      else delete next[key];
      return next;
    });
  }, []);

  const clear = useCallback(() => setErrors({}), []);

  return { errors, validate, revalidate, set, clear };
}
