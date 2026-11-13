'use client';

import { useRouter } from 'next/navigation';
import { Chip } from '../Chip';
import { ErrorState } from '../ErrorState';
import { type ChangeEvent, useEffect, useRef, useState } from 'react';
import { getMyProvider, saveBeforeAfters, saveGallery } from '../../lib/api/pro';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import {
  type BeforeAfterPair,
  canAddPair,
  canAddPhoto,
  insertAt,
  moveItem,
  removeAt,
  toCover,
} from '../../lib/pro/medias';
import { uploadFailureMessage, uploadGalleryImage } from '../../lib/pro/upload';
import { useFocusBackAfter, useLeaveSignal } from '../../lib/pro/upload-hooks';
import { Button } from '../Button';
import { Modal } from '../Modal';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';
import { SkeletonGrid } from '../Skeleton';
import { TextField } from '../TextField';
import { Tabs } from '../Tabs';

type Tab = 'photos' | 'avant-apres';

const MEDIA_TABS: { key: Tab; label: string }[] = [
  { key: 'photos', label: 'Photos' },
  { key: 'avant-apres', label: 'Avant / Après' },
];

/// Médias — like the app (docs/design/web-pro-medias-like-app.md, owner
/// decision): every gesture saves at once, as `pro_photos_screen.dart` and
/// `pro_before_after_screen.dart` do; deleting asks first, in the app's words,
/// then « Annuler » for 10 s puts the ONE removed item back into the list as
/// it is then (SYSTEM §15). A refused write puts back what the server holds.
/// There is no « Enregistrer » any more — nothing can be lost on leaving.
export function MediasClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [photos, setPhotos] = useState<string[]>([]);
  const [pairs, setPairs] = useState<BeforeAfterPair[]>([]);
  // What the server last accepted — where a refused write goes back to, and
  // the list an undo puts its item back into.
  const savedPhotos = useRef<string[]>([]);
  const savedPairs = useRef<BeforeAfterPair[]>([]);
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<Tab>('photos');
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState<LoadFailure | false>(false);
  const [confirming, setConfirming] = useState<
    { kind: 'photo' | 'pair'; index: number } | null
  >(null);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const { toast, show, dismiss } = useToast();
  // Leaving Médias (not switching its tabs) stops an upload in progress:
  // nothing is signed, sent or added after that (web-pro-upload-resize.md §2.4).
  const leaving = useLeaveSignal();

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
        setLoadError(loadFailure(me.status));
        setLoading(false);
        return;
      }
      setProviderId(me.profile.provider.id);
      const loadedPhotos = me.profile.provider.imageUrls ?? [];
      const loadedPairs = me.profile.provider.beforeAfters ?? [];
      savedPhotos.current = loadedPhotos;
      savedPairs.current = loadedPairs;
      setPhotos(loadedPhotos);
      setPairs(loadedPairs);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey]);

  /// What the server STORED becomes what the page holds — never `next`.
  ///
  /// `next` carries a just-uploaded photo at its `pending/…` address; the save
  /// moves it and deletes that object. Keeping `next` made the following save
  /// re-send a dead address, refused in production on 2026-11-13 for every add
  /// after the first (docs/design/upload-resave-stale-pending.md). A 2xx that
  /// did not carry the list reads the salon back instead.
  async function adoptStored(
    stored: { photos?: string[]; pairs?: BeforeAfterPair[] },
  ): Promise<void> {
    if (stored.photos) {
      savedPhotos.current = stored.photos;
      setPhotos(stored.photos);
      return;
    }
    if (stored.pairs) {
      savedPairs.current = stored.pairs;
      setPairs(stored.pairs);
      return;
    }
    const me = await getMyProvider();
    if (me.status !== 200 || !me.profile) {
      // Neither answer is usable: the full reload shows the page's own error.
      setLoading(true);
      setReloadKey((k) => k + 1);
      return;
    }
    savedPhotos.current = me.profile.provider.imageUrls ?? [];
    savedPairs.current = me.profile.provider.beforeAfters ?? [];
    setPhotos(savedPhotos.current);
    setPairs(savedPairs.current);
  }

  /// One write at a time: the controls wait while it is out.
  async function writePhotos(next: string[], failure: string): Promise<boolean> {
    setBusy(true);
    setPhotos(next);
    const r = await saveGallery(providerId, next);
    if (!r.ok) {
      setBusy(false);
      setPhotos(savedPhotos.current);
      show(failure, 'error');
      return false;
    }
    await adoptStored(r.stored ? { photos: r.stored } : {});
    setBusy(false);
    return true;
  }

  async function writePairs(next: BeforeAfterPair[], failure: string): Promise<boolean> {
    setBusy(true);
    setPairs(next);
    const r = await saveBeforeAfters(providerId, next);
    if (!r.ok) {
      setBusy(false);
      setPairs(savedPairs.current);
      show(failure, 'error');
      return false;
    }
    await adoptStored(r.stored ? { pairs: r.stored } : {});
    setBusy(false);
    return true;
  }

  async function confirmDelete() {
    const target = confirming;
    setConfirming(null);
    if (!target) return;
    const i = target.index;
    if (target.kind === 'photo') {
      const removed = savedPhotos.current[i];
      if (!(await writePhotos(removeAt(savedPhotos.current, i), 'Suppression impossible.'))) return;
      show('Photo supprimée', 'success', {
        label: 'Annuler',
        onAction: () => {
          dismiss();
          void writePhotos(insertAt(savedPhotos.current, i, removed), 'Restauration impossible.');
        },
      });
    } else {
      const removed = savedPairs.current[i];
      if (!(await writePairs(removeAt(savedPairs.current, i), 'Suppression impossible.'))) return;
      show('Avant/après supprimé', 'success', {
        label: 'Annuler',
        onAction: () => {
          dismiss();
          void writePairs(insertAt(savedPairs.current, i, removed), 'Restauration impossible.');
        },
      });
    }
  }

  if (loading) return <SkeletonGrid count={6} className="mt-l grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4" />;
  if (loadError) {
    return <ErrorState title="Médias" message={loadFailureMessage(loadError)} onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Médias</h1>

      <Tabs
        label="Type de média"
        className="mt-l"
        value={tab}
        onChange={setTab}
        items={MEDIA_TABS}
      />

      {tab === 'photos' ? (
        <PhotosTab
          photos={photos}
          busy={busy}
          leaving={leaving}
          onWrite={(next, failure) => void writePhotos(next, failure)}
          onAdd={async (url) => {
            await writePhotos([...savedPhotos.current, url], 'Échec de l’envoi');
          }}
          onUploadFailed={(message) => show(message, 'error')}
          onDelete={(index) => setConfirming({ kind: 'photo', index })}
        />
      ) : (
        <AvantApresTab
          pairs={pairs}
          busy={busy}
          leaving={leaving}
          onAdd={(pair) => writePairs([...savedPairs.current, pair], 'Échec de l’enregistrement')}
          onUploadFailed={(message) => show(message, 'error')}
          onDelete={(index) => setConfirming({ kind: 'pair', index })}
        />
      )}

      {confirming ? (
        // The app's question, word for word (§15: name it, say what happens,
        // the verb on the button; « Annuler » takes the focus).
        <Modal
          title={confirming.kind === 'photo' ? 'Supprimer cette photo ?' : 'Supprimer cette paire ?'}
          onClose={() => setConfirming(null)}
          initialFocusRef={cancelRef}
        >
          <p className="mt-m text-bodyMedium text-textSecondary">
            {confirming.kind === 'photo'
              ? 'Elle disparaîtra de votre galerie publique.'
              : 'L’avant/après disparaîtra de votre galerie publique.'}
          </p>
          <div className="mt-l flex flex-wrap justify-end gap-s">
            <Button ref={cancelRef} variant="secondary" onClick={() => setConfirming(null)}>
              Annuler
            </Button>
            <Button onClick={() => void confirmDelete()} className="!bg-error hover:!bg-error">
              {confirming.kind === 'photo' ? 'Supprimer la photo' : 'Supprimer la paire'}
            </Button>
          </div>
        </Modal>
      ) : null}
      <Toast toast={toast} />
    </div>
  );
}

function PhotosTab({
  photos,
  busy,
  leaving,
  onWrite,
  onAdd,
  onUploadFailed,
  onDelete,
}: {
  photos: string[];
  busy: boolean;
  leaving: () => AbortSignal;
  onWrite: (next: string[], failure: string) => void;
  onAdd: (url: string) => Promise<void>;
  onUploadFailed: (message: string) => void;
  onDelete: (index: number) => void;
}) {
  const [uploading, setUploading] = useState(false);
  const pickRef = useRef<HTMLInputElement>(null);
  // The input is disabled while it works; the focus comes back to it after.
  useFocusBackAfter(uploading, pickRef);

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(true);
    // Prepared as the app does before it is sent (web-pro-upload-resize.md).
    const signal = leaving();
    const upload = await uploadGalleryImage(file, { signal });
    if (signal.aborted) return; // Médias was left: nothing is added
    if (!upload.ok) {
      setUploading(false);
      onUploadFailed(uploadFailureMessage(upload.reason, 'Échec de l’envoi'));
      return;
    }
    await onAdd(upload.url);
    setUploading(false);
  }

  return (
    <div className="mt-m">
      <p className="text-bodyMedium text-textTertiary">
        Ajoutez au moins 3 photos. La première sert de couverture.
      </p>

      <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">
        {photos.map((url, i) => (
          <div
            key={`${url}-${i}`}
            className="overflow-hidden rounded-xl border border-border bg-secondary"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={url} alt="" className="h-40 w-full object-cover sm:h-32" />
            <div className="flex flex-wrap items-center justify-between gap-s p-s">
              {i === 0 ? (
                <Chip>
                  Couverture
                </Chip>
              ) : (
                <span />
              )}
              <span className="flex gap-s">
                {i > 0 ? (
                  // gallery-set-cover.md: one click instead of i « Monter »s
                  // — saved at once, as in the app.
                  <IconBtn
                    label="Définir comme photo principale"
                    disabled={busy}
                    onClick={() => onWrite(toCover(photos, i), 'Échec du déplacement')}
                  >
                    ★
                  </IconBtn>
                ) : null}
                <IconBtn
                  label="Monter"
                  disabled={busy}
                  onClick={() => onWrite(moveItem(photos, i, -1), 'Échec du déplacement')}
                >
                  ↑
                </IconBtn>
                <IconBtn
                  label="Descendre"
                  disabled={busy}
                  onClick={() => onWrite(moveItem(photos, i, 1), 'Échec du déplacement')}
                >
                  ↓
                </IconBtn>
                <IconBtn label="Supprimer" disabled={busy} onClick={() => onDelete(i)}>
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
          <label className="cursor-pointer min-h-12 rounded-control border border-primary bg-surface p-m text-bodyMedium text-textPrimary focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-borderFocus hover:bg-surfaceVariant">
            {uploading ? 'Téléversement…' : 'Ajouter une photo'}
            <input
              ref={pickRef}
              type="file"
              accept="image/*"
              className="sr-only"
              disabled={busy || uploading}
              onChange={onPick}
            />
          </label>
        ) : (
          <span className="text-bodyMedium text-textTertiary">Maximum atteint.</span>
        )}
      </div>
    </div>
  );
}

function AvantApresTab({
  pairs,
  busy,
  leaving,
  onAdd,
  onUploadFailed,
  onDelete,
}: {
  pairs: BeforeAfterPair[];
  busy: boolean;
  leaving: () => AbortSignal;
  onAdd: (pair: BeforeAfterPair) => Promise<boolean>;
  onUploadFailed: (message: string) => void;
  onDelete: (index: number) => void;
}) {
  const [before, setBefore] = useState<string | null>(null);
  const [after, setAfter] = useState<string | null>(null);
  const [caption, setCaption] = useState('');
  // Which side is on its way: that picker says « Téléversement… » and both
  // wait, as the app's add button does while it sends (§2.3).
  const [uploading, setUploading] = useState<'before' | 'after' | null>(null);

  async function pick(
    e: ChangeEvent<HTMLInputElement>,
    side: 'before' | 'after',
    set: (u: string | null) => void,
  ) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(side);
    const signal = leaving();
    const upload = await uploadGalleryImage(file, { signal });
    if (signal.aborted) return; // Médias was left
    setUploading(null);
    if (!upload.ok) {
      onUploadFailed(uploadFailureMessage(upload.reason, 'Échec de l’envoi'));
      return;
    }
    set(upload.url);
  }

  async function addPair() {
    if (!before || !after) return;
    const ok = await onAdd({ before, after, caption: caption.trim() || undefined });
    if (!ok) return; // what was picked stays, to try again
    setBefore(null);
    setAfter(null);
    setCaption('');
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
            <IconBtn label="Supprimer" disabled={busy} onClick={() => onDelete(i)}>
              ✕
            </IconBtn>
          </div>
        ))}
      </div>

      {canAddPair(pairs) ? (
        <div className="mt-m rounded-xl border border-border bg-secondary p-m">
          <p className="text-bodyMedium text-textTertiary">Ajouter une paire</p>
          <div className="mt-s flex flex-wrap items-center gap-m">
            <FilePick
              label={before ? 'Avant ✓' : 'Avant'}
              busy={uploading === 'before'}
              disabled={uploading !== null}
              onChange={(e) => pick(e, 'before', setBefore)}
            />
            <FilePick
              label={after ? 'Après ✓' : 'Après'}
              busy={uploading === 'after'}
              disabled={uploading !== null}
              onChange={(e) => pick(e, 'after', setAfter)}
            />
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
              disabled={!before || !after || uploading !== null || busy}
              onClick={() => void addPair()}
            >
              Ajouter la paire
            </Button>
          </div>
        </div>
      ) : (
        <p className="mt-m text-bodyMedium text-textTertiary">Maximum atteint (12).</p>
      )}
    </div>
  );
}

function IconBtn({
  label,
  onClick,
  disabled,
  children,
}: {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  children: string;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      // Its children are always a glyph (↑ ↓ ✕) — an icon, not body text.
      // 14 → 16 by §7 (nearest; ties round up).
      className="flex min-h-12 min-w-12 items-center justify-center rounded-control border border-primary bg-surface text-iconXS text-textPrimary hover:bg-surfaceVariant disabled:border-border disabled:text-textDisabled"
    >
      {children}
    </button>
  );
}

function FilePick({
  label,
  busy,
  disabled,
  onChange,
}: {
  label: string;
  /// This side is being prepared and sent: « Téléversement… », as « Photos ».
  busy: boolean;
  disabled: boolean;
  onChange: (e: ChangeEvent<HTMLInputElement>) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  useFocusBackAfter(busy, inputRef);
  return (
    <label className="cursor-pointer min-h-12 rounded-control border border-primary bg-surface p-m text-bodyMedium text-textPrimary focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-borderFocus hover:bg-surfaceVariant">
      {busy ? 'Téléversement…' : label}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="sr-only"
        disabled={disabled}
        onChange={onChange}
      />
    </label>
  );
}
