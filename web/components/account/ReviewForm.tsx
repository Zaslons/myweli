'use client';

import { useState } from 'react';
import { isValidRating } from '../../lib/account/extras';
import { submitReview } from '../../lib/api/account';
import { Button } from '../Button';

/// Leave a review on a completed booking (1–5 stars + optional text).
export function ReviewForm({ appointmentId }: { appointmentId: string }) {
  const [rating, setRating] = useState(0);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit() {
    if (!isValidRating(rating)) {
      setError('Sélectionnez une note (1 à 5 étoiles).');
      return;
    }
    setBusy(true);
    setError(null);
    const r = await submitReview(appointmentId, {
      rating,
      text: text.trim() || undefined,
    });
    setBusy(false);
    if (!r.ok) {
      setError('L’envoi a échoué. Réessayez.');
      return;
    }
    setDone(true);
  }

  if (done) {
    return (
      <p className="text-sm text-textSecondary">Merci pour votre avis&nbsp;!</p>
    );
  }

  return (
    <div>
      <p className="font-medium text-textPrimary">Laisser un avis</p>
      <div className="mt-s flex gap-xs" role="radiogroup" aria-label="Note">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            aria-label={`${n} étoile${n > 1 ? 's' : ''}`}
            aria-pressed={rating >= n}
            onClick={() => setRating(n)}
            className={`text-2xl ${rating >= n ? 'text-textPrimary' : 'text-textTertiary'}`}
          >
            ★
          </button>
        ))}
      </div>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={3}
        placeholder="Votre expérience (optionnel)"
        className="mt-s w-full rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
      />
      {error ? <p className="mt-xs text-sm text-error">{error}</p> : null}
      <div className="mt-s">
        <Button disabled={busy} onClick={submit}>
          Envoyer l’avis
        </Button>
      </div>
    </div>
  );
}
