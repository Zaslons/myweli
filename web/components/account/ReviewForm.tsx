'use client';

import { useRef, useState } from 'react';
import { isValidRating } from '../../lib/account/extras';
import {
  addPhoto,
  canAddPhoto,
  removePhoto,
  uploadReviewPhoto,
} from '../../lib/account/review-photos';
import { submitReview } from '../../lib/api/account';
import { Button } from '../Button';

/// Leave a review on a completed booking (1–5 stars + optional text +
/// up to 3 photos — the app's submit sheet, parity 2.13).
export function ReviewForm({ appointmentId }: { appointmentId: string }) {
  const [rating, setRating] = useState(0);
  const [text, setText] = useState('');
  const [photos, setPhotos] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function onPickPhoto(file: File | undefined) {
    if (!file || !canAddPhoto(photos)) return;
    setUploading(true);
    setError(null);
    const url = await uploadReviewPhoto(file);
    setUploading(false);
    if (!url) {
      setError('Échec de l’envoi de la photo. Réessayez.');
      return;
    }
    setPhotos((cur) => addPhoto(cur, url));
  }

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
      photoUrls: photos.length > 0 ? photos : undefined,
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
      {/* Photos (≤3), like the app's sheet. */}
      <div className="mt-s">
        {photos.length > 0 ? (
          <div className="flex gap-s">
            {photos.map((url, i) => (
              <span key={url} className="relative">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={url}
                  alt={`Photo ${i + 1}`}
                  className="h-16 w-16 rounded-lg object-cover"
                />
                <button
                  type="button"
                  aria-label={`Retirer la photo ${i + 1}`}
                  onClick={() => setPhotos((cur) => removePhoto(cur, i))}
                  className="absolute -right-1 -top-1 rounded-pill bg-primary px-xs text-xs text-secondary"
                >
                  ✕
                </button>
              </span>
            ))}
          </div>
        ) : null}
        {canAddPhoto(photos) ? (
          <div className="mt-s">
            <input
              ref={fileRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              aria-label="Photo de l’avis"
              onChange={(e) => {
                onPickPhoto(e.target.files?.[0]);
                e.target.value = '';
              }}
            />
            <Button
              variant="secondary"
              disabled={uploading}
              onClick={() => fileRef.current?.click()}
            >
              {uploading ? 'Envoi…' : 'Ajouter une photo'}
            </Button>
          </div>
        ) : null}
      </div>
      {error ? <p className="mt-xs text-sm text-error">{error}</p> : null}
      <div className="mt-s">
        <Button disabled={busy || uploading} onClick={submit}>
          Envoyer l’avis
        </Button>
      </div>
    </div>
  );
}
