'use client';

import { useRouter } from 'next/navigation';
import { type ChangeEvent, useEffect, useState } from 'react';
import { getMyProvider, saveBeforeAfters, saveGallery } from '../../lib/api/pro';
import {
  type BeforeAfterPair,
  canAddPair,
  canAddPhoto,
  moveItem,
  removeAt,
} from '../../lib/pro/medias';
import { uploadGalleryImage } from '../../lib/pro/upload';
import { Button } from '../Button';
import { TextField } from '../TextField';

type Tab = 'photos' | 'avant-apres';

export function MediasClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [photos, setPhotos] = useState<string[]>([]);
  const [pairs, setPairs] = useState<BeforeAfterPair[]>([]);
  const [tab, setTab] = useState<Tab>('photos');
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (!active) return;
      if (me.status !== 200 || !me.profile) {
        setLoadError(true);
        setLoading(false);
        return;
      }
      setProviderId(me.profile.provider.id);
      setPhotos(me.profile.provider.imageUrls ?? []);
      setPairs(me.profile.provider.beforeAfters ?? []);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (loadError) {
    return <p role="alert" className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Médias</h1>

      <div className="mt-l flex gap-s border-b border-divider">
        {(
          [
            { key: 'photos', label: 'Photos' },
            { key: 'avant-apres', label: 'Avant / Après' },
          ] as { key: Tab; label: string }[]
        ).map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`px-m py-s text-bodyMedium ${
              tab === t.key
                ? 'border-b-2 border-primary text-textPrimary'
                : 'text-textTertiary'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'photos' ? (
        <PhotosTab
          providerId={providerId}
          photos={photos}
          setPhotos={setPhotos}
        />
      ) : (
        <AvantApresTab
          providerId={providerId}
          pairs={pairs}
          setPairs={setPairs}
        />
      )}
    </div>
  );
}

function PhotosTab({
  providerId,
  photos,
  setPhotos,
}: {
  providerId: string;
  photos: string[];
  setPhotos: (p: string[]) => void;
}) {
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(true);
    setError(null);
    setSaved(false);
    const url = await uploadGalleryImage(file);
    setUploading(false);
    if (!url) {
      setError('Le téléversement a échoué.');
      return;
    }
    setPhotos([...photos, url]);
  }

  async function save() {
    setBusy(true);
    setError(null);
    const r = await saveGallery(providerId, photos);
    setBusy(false);
    if (!r.ok) {
      setError('L’enregistrement a échoué.');
      return;
    }
    setSaved(true);
  }

  return (
    <div className="mt-m">
      <p className="text-bodyMedium text-textTertiary">
        Ajoutez au moins 3 photos. La première sert de couverture.
      </p>

      <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3">
        {photos.map((url, i) => (
          <div
            key={`${url}-${i}`}
            className="overflow-hidden rounded-xl border border-border bg-secondary"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={url} alt="" className="h-40 w-full object-cover sm:h-32" />
            <div className="flex flex-wrap items-center justify-between gap-s p-s">
              {i === 0 ? (
                <span className="rounded-pill bg-surface px-s py-xs text-bodySmall text-textSecondary">
                  Couverture
                </span>
              ) : (
                <span />
              )}
              <span className="flex gap-s">
                <IconBtn
                  label="Monter"
                  onClick={() => setPhotos(moveItem(photos, i, -1))}
                >
                  ↑
                </IconBtn>
                <IconBtn
                  label="Descendre"
                  onClick={() => setPhotos(moveItem(photos, i, 1))}
                >
                  ↓
                </IconBtn>
                <IconBtn
                  label="Supprimer"
                  onClick={() => setPhotos(removeAt(photos, i))}
                >
                  ✕
                </IconBtn>
              </span>
            </div>
          </div>
        ))}
      </div>

      <div className="mt-m flex flex-wrap items-center gap-s">
        {canAddPhoto(photos) ? (
          // Row 22: `hidden` (display:none) made the input unfocusable — a
          // keyboard user could not upload at all. sr-only keeps it a real
          // tab stop; §5's ring projects onto the label via focus-within.
          <label className="cursor-pointer min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-borderFocus hover:bg-surfaceVariant">
            {uploading ? 'Téléversement…' : 'Ajouter une photo'}
            <input
              type="file"
              accept="image/*"
              className="sr-only"
              onChange={onPick}
            />
          </label>
        ) : (
          <span className="text-bodyMedium text-textTertiary">Maximum atteint.</span>
        )}
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </div>

      {error ? <p role="alert" className="mt-s text-bodyMedium text-error">{error}</p> : null}
      <p
        role="status"
        className={saved ? 'mt-s text-bodyMedium text-textSecondary' : 'sr-only'}
      >
        {saved ? 'Photos enregistrées.' : ''}
      </p>
    </div>
  );
}

function AvantApresTab({
  providerId,
  pairs,
  setPairs,
}: {
  providerId: string;
  pairs: BeforeAfterPair[];
  setPairs: (p: BeforeAfterPair[]) => void;
}) {
  const [before, setBefore] = useState<string | null>(null);
  const [after, setAfter] = useState<string | null>(null);
  const [caption, setCaption] = useState('');
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function pick(
    e: ChangeEvent<HTMLInputElement>,
    set: (u: string | null) => void,
  ) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(true);
    setError(null);
    const url = await uploadGalleryImage(file);
    setUploading(false);
    if (!url) {
      setError('Le téléversement a échoué.');
      return;
    }
    set(url);
  }

  function addPair() {
    if (!before || !after) return;
    setPairs([...pairs, { before, after, caption: caption.trim() || undefined }]);
    setBefore(null);
    setAfter(null);
    setCaption('');
    setSaved(false);
  }

  async function save() {
    setBusy(true);
    setError(null);
    const r = await saveBeforeAfters(providerId, pairs);
    setBusy(false);
    if (!r.ok) {
      setError('L’enregistrement a échoué.');
      return;
    }
    setSaved(true);
  }

  return (
    <div className="mt-m">
      <div className="space-y-s">
        {pairs.map((p, i) => (
          <div
            key={`${p.before}-${i}`}
            className="flex items-center gap-m rounded-xl border border-border bg-secondary p-s"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.before} alt="" className="h-16 w-16 rounded-sm object-cover" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.after} alt="" className="h-16 w-16 rounded-sm object-cover" />
            <span className="flex-1 text-bodyMedium text-textTertiary">
              {p.caption ?? ''}
            </span>
            <IconBtn label="Supprimer" onClick={() => setPairs(removeAt(pairs, i))}>
              ✕
            </IconBtn>
          </div>
        ))}
      </div>

      {canAddPair(pairs) ? (
        <div className="mt-m rounded-xl border border-border bg-secondary p-m">
          <p className="text-bodyMedium text-textTertiary">Ajouter une paire</p>
          <div className="mt-s flex flex-wrap items-center gap-m">
            <FilePick label={before ? 'Avant ✓' : 'Avant'} onChange={(e) => pick(e, setBefore)} />
            <FilePick label={after ? 'Après ✓' : 'Après'} onChange={(e) => pick(e, setAfter)} />
            <TextField
              label="Légende (optionnelle)"
              hideLabel
              type="text"
              placeholder="Légende (optionnelle)"
              value={caption}
              onChange={(e) => setCaption(e.target.value)}
            />
            <Button
              variant="secondary"
              disabled={!before || !after || uploading}
              onClick={addPair}
            >
              Ajouter la paire
            </Button>
          </div>
        </div>
      ) : (
        <p className="mt-m text-bodyMedium text-textTertiary">Maximum atteint (12).</p>
      )}

      <div className="mt-m">
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </div>
      {error ? <p role="alert" className="mt-s text-bodyMedium text-error">{error}</p> : null}
      <p
        role="status"
        className={saved ? 'mt-s text-bodyMedium text-textSecondary' : 'sr-only'}
      >
        {saved ? 'Avant/Après enregistré.' : ''}
      </p>
    </div>
  );
}

function IconBtn({
  label,
  onClick,
  children,
}: {
  label: string;
  onClick: () => void;
  children: string;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      // Its children are always a glyph (↑ ↓ ✕) — an icon, not body text.
      // 14 → 16 by §7 (nearest; ties round up).
      className="flex min-h-12 min-w-12 items-center justify-center rounded-sm border border-borderStrong bg-surface text-iconXS text-textPrimary hover:bg-surfaceVariant"
    >
      {children}
    </button>
  );
}

function FilePick({
  label,
  onChange,
}: {
  label: string;
  onChange: (e: ChangeEvent<HTMLInputElement>) => void;
}) {
  return (
    <label className="cursor-pointer min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-borderFocus hover:bg-surfaceVariant">
      {label}
      <input type="file" accept="image/*" className="sr-only" onChange={onChange} />
    </label>
  );
}
