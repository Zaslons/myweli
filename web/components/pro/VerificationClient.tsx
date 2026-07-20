'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { getKycStatus, getMyProvider, submitKyc } from '../../lib/api/pro';
import {
  KYC_ACCEPT,
  KYC_DOC_TYPES,
  type KycDocType,
  type KycStatus,
  canSubmitKyc,
  isKycDocRequired,
} from '../../lib/pro/kyc';
import { uploadKycDocument } from '../../lib/pro/upload';
import { Button } from '../Button';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';

type LocalDoc = { type: KycDocType; fileName?: string; key: string };

/// « Vérification » (docs/design/web-pro-kyc.md) — the pro app's ProKycScreen,
/// web-adapted: status banner + the four document tiles (upload at add time,
/// « Soumettre pour vérification » posts the full list). Verified = read-only.
export function VerificationClient() {
  const router = useRouter();
  const [businessType, setBusinessType] = useState<string | null>(null);
  const [status, setStatus] = useState<KycStatus['status']>('pending');
  const [rejectionReason, setRejectionReason] = useState<string | null>(null);
  const [docs, setDocs] = useState<LocalDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [uploadingType, setUploadingType] = useState<KycDocType | null>(null);
  const [uploadError, setUploadError] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const { toast, show } = useToast();
  const inputs = useRef<Partial<Record<KycDocType, HTMLInputElement | null>>>(
    {},
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    const kyc = await getKycStatus();
    if (me.status !== 200 || !me.profile || kyc.status !== 200 || !kyc.kyc) {
      setError(true);
      setLoading(false);
      return;
    }
    setBusinessType(me.profile.account.businessType ?? null);
    setStatus(kyc.kyc.status);
    setRejectionReason(kyc.kyc.rejectionReason ?? null);
    setDocs(
      kyc.kyc.documents.map((d) => ({
        type: d.type,
        fileName: d.fileName,
        key: d.key,
      })),
    );
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);


  const verified = status === 'verified';

  async function onFile(type: KycDocType, file: File | undefined) {
    if (!file) return;
    setUploadingType(type);
    setUploadError(false);
    const up = await uploadKycDocument(file);
    setUploadingType(null);
    if (!up) {
      setUploadError(true);
      return;
    }
    setDocs((prev) => [
      ...prev.filter((d) => d.type !== type),
      { type, fileName: up.fileName, key: up.key },
    ]);
  }

  async function submit() {
    setSubmitting(true);
    const r = await submitKyc(docs);
    setSubmitting(false);
    if (r.status !== 200 || !r.kyc) {
      show('L’envoi a échoué. Réessayez.', 'error');
      return;
    }
    setStatus(r.kyc.status);
    setRejectionReason(r.kyc.rejectionReason ?? null);
    show('Documents soumis pour vérification', 'success');
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return (
      <div>
        <p role="alert" className="text-error">Chargement impossible.</p>
        <div className="mt-s">
          <Button variant="secondary" onClick={load}>
            Réessayer
          </Button>
        </div>
      </div>
    );
  }

  const banner = verified
    ? {
        cls: 'border-success/40 bg-success/10 text-success',
        title: 'Compte vérifié',
        subtitle: 'Vous pouvez activer les acomptes.',
      }
    : status === 'rejected'
      ? {
          cls: 'border-error/40 bg-error/10 text-error',
          title: 'Vérification refusée',
          subtitle: rejectionReason ?? 'Veuillez renvoyer vos documents.',
        }
      : {
          cls: 'border-border bg-surface text-textSecondary',
          title: 'Vérification en attente',
          subtitle: 'Soumettez vos documents pour être vérifié.',
        };

  const canSubmit = canSubmitKyc({
    documents: docs,
    businessType,
    status,
    busy: submitting || uploadingType != null,
  });

  return (
    <div className="max-w-2xl">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Vérification</h1>

      <div className={`mt-l rounded-xl border p-m ${banner.cls}`}>
        <p className="font-medium">{banner.title}</p>
        <p className="mt-xs text-bodyMedium">{banner.subtitle}</p>
      </div>

      <p className="mt-l text-labelMedium font-medium uppercase text-textTertiary">
        Documents
      </p>
      <ul className="mt-xs space-y-s">
        {KYC_DOC_TYPES.map(({ type, label }) => {
          const required = isKycDocRequired(type, businessType);
          const doc = docs.find((d) => d.type === type);
          const uploading = uploadingType === type;
          return (
            <li
              key={type}
              className="flex items-center justify-between gap-m rounded-xl border border-border bg-secondary p-m"
            >
              <div className="min-w-0">
                <p className="text-bodyMedium text-textPrimary">
                  {label}
                  {required ? '' : ' (optionnel)'}
                </p>
                <p
                  className={`mt-xs truncate text-bodySmall ${
                    doc ? 'text-success' : 'text-textTertiary'
                  }`}
                >
                  {doc ? `Fourni · ${doc.fileName ?? 'document'}` : 'À fournir'}
                </p>
              </div>
              {!verified ? (
                <div className="flex shrink-0 items-center gap-s">
                  {doc ? (
                    <button
                      type="button"
                      aria-label={`Retirer ${label}`}
                      className="text-bodyMedium text-textTertiary underline"
                      onClick={() =>
                        setDocs((prev) => prev.filter((d) => d.type !== type))
                      }
                    >
                      Retirer
                    </button>
                  ) : null}
                  <input
                    ref={(el) => {
                      inputs.current[type] = el;
                    }}
                    type="file"
                    accept={KYC_ACCEPT}
                    aria-label={label}
                    className="hidden"
                    onChange={(e) => onFile(type, e.target.files?.[0])}
                  />
                  <Button
                    variant="secondary"
                    disabled={uploading}
                    onClick={() => inputs.current[type]?.click()}
                  >
                    {uploading ? 'Envoi…' : doc ? 'Modifier' : 'Ajouter'}
                  </Button>
                </div>
              ) : null}
            </li>
          );
        })}
      </ul>
      {uploadError ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          Échec de l’envoi du document. Réessayez.
        </p>
      ) : null}

      <p className="mt-m text-bodySmall text-textTertiary">
        Les acomptes sont activés une fois votre compte vérifié. Vos documents
        sont chiffrés et confidentiels.
      </p>

      {!verified ? (
        <div className="mt-l">
          <Button disabled={!canSubmit} onClick={submit}>
            {submitting ? 'Envoi…' : 'Soumettre pour vérification'}
          </Button>
          {!canSubmit && !submitting && uploadingType == null ? (
            <p className="mt-xs text-bodySmall text-textTertiary">
              Ajoutez les documents requis pour soumettre.
            </p>
          ) : null}
        </div>
      ) : null}

      <Toast toast={toast} />
    </div>
  );
}
